output "resource_location_id" {
  description = "ID of the Citrix Cloud resource location"
  value       = citrix_cloud_resource_location.this.id
}

output "zone_id" {
  description = "ID of the Citrix DaaS zone"
  value       = citrix_zone.this.id
}

output "hypervisor_id" {
  description = "ID of the Azure hosting connection"
  value       = citrix_azure_hypervisor.this.id
}

output "resource_pool_id" {
  description = "ID of the Azure hypervisor resource pool"
  value       = citrix_azure_hypervisor_resource_pool.this.id
}

output "image_definition_id" {
  description = "ID of the Citrix image definition"
  value       = citrix_image_definition.vda.id
}

output "image_version_ids" {
  description = "IDs of the Citrix image versions, keyed by build label (e.g. \"2607-1\") - one entry per unique gallery image version across all environments, not per (environment, label) pair"
  value       = { for label, v in citrix_image_version.vda : label => v.id }
}

output "machine_catalog_ids" {
  description = "IDs of the machine catalogs, keyed by \"<environment>-<label>\" (e.g. \"dev-2607-1\")"
  value       = { for key, mc in citrix_machine_catalog.vda : key => mc.id }
}

output "delivery_group_ids" {
  description = "IDs of the delivery groups desktops are published through, keyed by environment (\"dev\"/\"test\"/\"prod\")"
  value       = { for env, dg in citrix_delivery_group.vda : env => dg.id }
}

output "vda_resource_group_names" {
  description = "Names of the per-catalog-build resource groups holding MCS-provisioned VDA VMs/NICs/disks, keyed by \"<environment>-<label>\" (e.g. \"dev-2607-1\")"
  value       = { for key, rg in azurerm_resource_group.vda : key => rg.name }
}
