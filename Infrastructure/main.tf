provider "azurerm" {
  features {}
  client_id       = var.ARM_CLIENT_ID
  client_secret   = var.ARM_CLIENT_SECRET
  subscription_id = var.ARM_SUBSCRIPTION_ID
  tenant_id       = var.ARM_TENANT_ID
}

resource "random_integer" "suffix" {
  min = 10000
  max = 99999
}

resource "azurerm_resource_group" "example" {
  name     = "example-resources-oliver${random_integer.suffix.result}"
  location = "East US"
}

# Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "exampleacr${random_integer.suffix.result}"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  sku                 = "Basic"
  admin_enabled       = true
}

# Azure Kubernetes Service
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "exampleaks${random_integer.suffix.result}"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  dns_prefix          = "exampleaks"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D4pds_v5"
  }

  identity {
    type = "SystemAssigned"
  }
}

# Azure Key Vault
resource "azurerm_key_vault" "example" {
  name                = "examplekeyvault${random_integer.suffix.result}"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  tenant_id           = var.ARM_TENANT_ID
  sku_name            = "standard"

  access_policy {
    tenant_id = var.ARM_TENANT_ID
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set"
    ]
  }
}

# Data source to get the current client's details
data "azurerm_client_config" "current" {}

# Azure Key Vault Secret for Redis Password
resource "azurerm_key_vault_secret" "redis_password" {
  name         = "redis-password"
  value        = "Password123xyz!"
  key_vault_id = azurerm_key_vault.example.id
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}


output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "redis_password_secret_id" {
  value = azurerm_key_vault_secret.redis_password.id
}

variable "images" {
  type = map(string)
  default = {
    "redis"           = "redis:latest"
    "redis-exporter"  = "oliver006/redis_exporter:latest"
    "prometheus"      = "prom/prometheus:latest"
    "grafana"         = "grafana/grafana:latest"
  }
}

resource "null_resource" "docker_images" {
  for_each = var.images

  triggers = {
    image_name = each.key
    image_tag  = each.value
  }

  provisioner "local-exec" {
    command = <<EOT
      docker pull ${each.value}
      docker tag ${each.value} ${azurerm_container_registry.acr.login_server}/${each.key}:latest
      az acr login --name ${azurerm_container_registry.acr.name}
      docker push ${azurerm_container_registry.acr.login_server}/${each.key}:latest
    EOT
  }

  depends_on = [azurerm_container_registry.acr]
}



# Kubernetes provider
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

# Connect AKS to ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

# Redis Deployment
resource "kubernetes_deployment" "redis" {
  metadata {
    name = "redis"
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "redis"
      }
    }
    template {
      metadata {
        labels = {
          app = "redis"
        }
      }
      spec {
        container {
          name  = "redis"
          image = "${azurerm_container_registry.acr.login_server}/redis:latest"
          port {
            container_port = 6379
          }
        }
      }
    }
  }
}

# Redis Service
resource "kubernetes_service" "redis" {
  metadata {
    name = "redis"
  }
  spec {
    selector = {
      app = "redis"
    }
    port {
      port        = 6379
      target_port = 6379
    }
  }
}

# Redis Exporter Deployment
resource "kubernetes_deployment" "redis_exporter" {
  metadata {
    name = "redis-exporter"
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "redis-exporter"
      }
    }
    template {
      metadata {
        labels = {
          app = "redis-exporter"
        }
      }
      spec {
        container {
          name  = "redis-exporter"
          image = "oliver006/redis_exporter:latest"
          port {
            container_port = 9121
          }
          env {
            name  = "REDIS_ADDR"
            value = "redis:6379"
          }
        }
      }
    }
  }
}

# Redis Exporter Service
resource "kubernetes_service" "redis_exporter" {
  metadata {
    name = "redis-exporter"
  }
  spec {
    selector = {
      app = "redis-exporter"
    }
    port {
      port        = 9121
      target_port = 9121
    }
  }
}

# Prometheus ConfigMap
resource "kubernetes_config_map" "prometheus_config" {
  metadata {
    name = "prometheus-config"
  }
  data = {
    "prometheus.yml" = <<-EOT
      global:
        scrape_interval: 15s
      scrape_configs:
        - job_name: 'redis'
          static_configs:
            - targets: ['redis-exporter:9121']
    EOT
  }
}

# Prometheus Deployment
resource "kubernetes_deployment" "prometheus" {
  metadata {
    name = "prometheus"
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "prometheus"
      }
    }
    template {
      metadata {
        labels = {
          app = "prometheus"
        }
      }
      spec {
        container {
          name  = "prometheus"
          image = "prom/prometheus:latest"
          port {
            container_port = 9090
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/prometheus/prometheus.yml"
            sub_path   = "prometheus.yml"
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.prometheus_config.metadata[0].name
          }
        }
      }
    }
  }
}

# Prometheus Service
resource "kubernetes_service" "prometheus" {
  metadata {
    name = "prometheus"
  }
  spec {
    selector = {
      app = "prometheus"
    }
    port {
      port        = 9090
      target_port = 9090
    }
  }
}

# Grafana ConfigMaps
resource "kubernetes_config_map" "grafana_datasources" {
  metadata {
    name = "grafana-datasources"
  }
  data = {
    "datasources.yaml" = <<-EOT
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          url: http://prometheus:9090
          access: proxy
          isDefault: true
    EOT
  }
}

resource "kubernetes_config_map" "grafana_dashboards_config" {
  metadata {
    name = "grafana-dashboards-config"
  }
  data = {
    "dashboards.yaml" = <<-EOT
      apiVersion: 1
      providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards
    EOT
  }
}

resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    name = "grafana-dashboards"
  }
  data = {
    "redis-dashboard.json" = <<-EOT
      {
        "dashboard": {
          "id": null,
          "title": "Redis Dashboard",
          "tags": ["redis"],
          "timezone": "browser",
          "schemaVersion": 16,
          "version": 0
        }
      }
    EOT
  }
}

# Grafana Deployment
resource "kubernetes_deployment" "grafana" {
  metadata {
    name = "grafana"
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "grafana"
      }
    }
    template {
      metadata {
        labels = {
          app = "grafana"
        }
      }
      spec {
        container {
          name  = "grafana"
          image = "grafana/grafana:latest"
          port {
            container_port = 3000
          }
          volume_mount {
            name       = "datasources"
            mount_path = "/etc/grafana/provisioning/datasources"
          }
          volume_mount {
            name       = "dashboards-config"
            mount_path = "/etc/grafana/provisioning/dashboards"
          }
          volume_mount {
            name       = "dashboards"
            mount_path = "/var/lib/grafana/dashboards"
          }
        }
        volume {
          name = "datasources"
          config_map {
            name = kubernetes_config_map.grafana_datasources.metadata[0].name
          }
        }
        volume {
          name = "dashboards-config"
          config_map {
            name = kubernetes_config_map.grafana_dashboards_config.metadata[0].name
          }
        }
        volume {
          name = "dashboards"
          config_map {
            name = kubernetes_config_map.grafana_dashboards.metadata[0].name
          }
        }
      }
    }
  }
}

# Grafana Service
resource "kubernetes_service" "grafana" {
  metadata {
    name = "grafana"
  }
  spec {
    selector = {
      app = "grafana"
    }
    port {
      port        = 3000
      target_port = 3000
    }
  }
}