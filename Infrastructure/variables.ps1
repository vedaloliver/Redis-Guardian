# Azure CLI Login
az login --tenant 53aa6af8-b761-4795-931e-6fcb087ddd26

# Retrieve Subscription ID
$subscriptionId = az account show --query id -o tsv

# Retrieve Tenant ID
$tenantId = az account show --query tenantId -o tsv

# Create a new service principal and get Client ID and Client Secret
$spInfo = az ad sp create-for-rbac --name "TerraformSP" --role Contributor --scope "/subscriptions/$subscriptionId" | ConvertFrom-Json

# Assign the "Contributor" role at the subscription level (if not already done in the previous step)
az role assignment create --assignee $spInfo.appId --role Contributor --scope "/subscriptions/$subscriptionId"

# Define the path for terraform.tfvars (adjust as needed)
$tfvarsPath = ".\terraform.tfvars"

# Update terraform.tfvars file with new values
@"
ARM_CLIENT_ID       = "$($spInfo.appId)"
ARM_CLIENT_SECRET   = "$($spInfo.password)"
ARM_SUBSCRIPTION_ID = "$subscriptionId"
ARM_TENANT_ID       = "$tenantId"
"@ | Set-Content -Path $tfvarsPath

# Output confirmation
Write-Host "terraform.tfvars has been updated with the new values."
Write-Host "File location: $tfvarsPath"

# Optional: Display the contents of terraform.tfvars (comment out if not needed)
Get-Content $tfvarsPath