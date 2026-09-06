# Outputs for the Citrix Azure environment

output "resource_group_name" {
  description = "The resource group created for Citrix resources"
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "Virtual network ID for the Citrix resource location"
  value       = module.network.vnet_id
}

output "nat_gateway_public_ip" {
  description = "Outbound public IP for the VDA subnet - use this if Citrix Cloud or a corporate firewall needs an egress IP allowlisted"
  value       = module.network.nat_gateway_public_ip
}

output "hosting_connection_client_id" {
  description = "Client ID of the Azure AD app registration used by the Citrix hosting connection"
  value       = module.identity.client_id
}

output "citrix_resource_location_id" {
  description = "ID of the Citrix Cloud resource location"
  value       = module.citrix.resource_location_id
}

output "citrix_zone_id" {
  description = "ID of the Citrix DaaS zone"
  value       = module.citrix.zone_id
}

output "citrix_hypervisor_id" {
  description = "ID of the Azure hosting connection"
  value       = module.citrix.hypervisor_id
}

output "citrix_resource_pool_id" {
  description = "ID of the Azure hypervisor resource pool"
  value       = module.citrix.resource_pool_id
}

output "citrix_image_definition_id" {
  description = "ID of the Citrix image definition"
  value       = module.citrix.image_definition_id
}

output "citrix_machine_catalog_ids" {
  description = "IDs of the machine catalogs, keyed by \"<environment>-<label>\" (e.g. \"dev-2607-1\")"
  value       = module.citrix.machine_catalog_ids
}

output "citrix_vda_resource_group_names" {
  description = "Names of the per-catalog-build resource groups holding MCS-provisioned VDA VMs/NICs/disks, keyed by \"<environment>-<label>\" (e.g. \"dev-2607-1\")"
  value       = module.citrix.vda_resource_group_names
}

output "citrix_delivery_group_ids" {
  description = "IDs of the delivery groups desktops are published through, keyed by environment (\"dev\"/\"test\"/\"prod\")"
  value       = module.citrix.delivery_group_ids
}

output "github_runner_vm_name" {
  description = "Name of the self-hosted GitHub Actions runner VM"
  value       = module.github_runner.vm_name
}

output "github_runner_private_ip_address" {
  description = "Private IP address of the self-hosted GitHub Actions runner VM"
  value       = module.github_runner.private_ip_address
}

output "github_runner_temporary_public_ip_address" {
  description = "Temporary public IP address of the runner VM, if enable_runner_temporary_ssh_access is true - null otherwise"
  value       = module.github_runner.temporary_public_ip_address
}

output "image_gallery_name" {
  description = "Name of the Shared Image Gallery Packer publishes VDA master images into"
  value       = module.image_gallery.gallery_name
}

output "image_definition_id" {
  description = "Resource ID of the VDA image definition - target this from the Packer build"
  value       = module.image_gallery.image_definition_id
}

output "artifact_storage_account_name" {
  description = "Name of the private storage account holding Packer image build artifacts"
  value       = module.artifact_storage.storage_account_name
}

output "artifact_storage_container_name" {
  description = "Name of the private blob container holding Packer image build artifacts - generate SAS URLs against this container for citrix_vda_installer_url / citrix_optimizer_zip_url"
  value       = module.artifact_storage.container_name
}

output "artifact_storage_primary_blob_endpoint" {
  description = "Primary blob endpoint of the artifact storage account"
  value       = module.artifact_storage.primary_blob_endpoint
}
