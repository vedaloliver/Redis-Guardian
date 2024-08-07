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
    vm_size    = "Standard_B2s" # Changed to a cost-effective option
  }

  identity {
    type = "SystemAssigned"
  }

  depends_on = [azurerm_role_assignment.kv_access]
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

# Role Assignment for Key Vault Access
resource "azurerm_role_assignment" "kv_access" {
  principal_id         = data.azurerm_client_config.current.object_id
  role_definition_name = "Key Vault Secrets User"
  scope                = azurerm_key_vault.example.id
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
