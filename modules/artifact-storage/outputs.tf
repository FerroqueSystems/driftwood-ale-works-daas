output "storage_account_id" {
  description = "Resource ID of the artifact storage account"
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the artifact storage account"
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Primary blob service endpoint for the artifact storage account"
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_name" {
  description = "Name of the private blob container holding image build artifacts - use this with the storage account to generate SAS URLs for Packer"
  value       = azurerm_storage_container.artifacts.name
}

output "container_id" {
  description = "Resource ID of the private blob container"
  value       = azurerm_storage_container.artifacts.id
}
