# Root environment configuration for Azure Citrix deployment.

# citrix_azure_hypervisor_resource_pool's `region` expects Azure's
# human-readable display name (e.g. "Canada Central"), not the short slug
# `azurerm` resources use for `location` (e.g. "canadacentral") - confirmed
# against https://github.com/citrix/terraform-provider-citrix's docs after a
# resource pool create failed with "Failed to resolve region canadacentral".
# Falls back to the raw value for any region not listed here.
locals {
  azure_region_display_names = {
    canadacentral  = "Canada Central"
    canadaeast     = "Canada East"
    eastus         = "East US"
    eastus2        = "East US 2"
    centralus      = "Central US"
    northcentralus = "North Central US"
    southcentralus = "South Central US"
    westcentralus  = "West Central US"
    westus         = "West US"
    westus2        = "West US 2"
    westus3        = "West US 3"
  }
  citrix_region = lookup(local.azure_region_display_names, var.location, var.location)
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

module "network" {
  source = "../../modules/network"

  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  vnet_name                   = var.vnet_name
  vnet_address_space          = var.vnet_address_space
  vda_subnet_address_prefixes = var.vda_subnet_address_prefixes
  tags                        = var.tags
}

module "identity" {
  source = "../../modules/identity"

  application_display_name = var.hosting_connection_app_name
  subscription_id          = var.azure_subscription_id
}

module "image_gallery" {
  source = "../../modules/image-gallery"

  resource_group_name   = azurerm_resource_group.this.name
  location              = azurerm_resource_group.this.location
  gallery_name          = var.gallery_name
  image_definition_name = var.image_definition_name
  image_sku             = var.image_sku
  tags                  = var.tags
}

module "artifact_storage" {
  source = "../../modules/artifact-storage"

  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  storage_account_name = var.artifact_storage_account_name
  container_name       = var.artifact_storage_container_name
  tags                 = var.tags
}

module "citrix" {
  source = "../../modules/citrix"

  resource_location_name   = var.citrix_resource_location_name
  zone_description         = var.citrix_zone_description
  hypervisor_name          = var.citrix_hypervisor_name
  subscription_id          = var.azure_subscription_id
  active_directory_id      = var.azure_tenant_id
  application_id           = module.identity.client_id
  application_secret       = module.identity.client_secret
  resource_pool_name       = var.citrix_resource_pool_name
  region                   = local.citrix_region
  vnet_name                = module.network.vnet_name
  vnet_resource_group_name = azurerm_resource_group.this.name
  subnets                  = [module.network.vda_subnet_name]

  image_gallery_name                = module.image_gallery.gallery_name
  image_gallery_resource_group_name = azurerm_resource_group.this.name
  image_definition_name             = var.image_definition_name
  image_versions                    = var.image_versions
  vda_resource_group_name           = azurerm_resource_group.this.name

  delivery_group_name                  = var.citrix_delivery_group_name
  allocation_type                      = var.citrix_allocation_type
  service_offering                     = var.citrix_vda_service_offering
  storage_type                         = var.citrix_vda_storage_type
  published_desktop_name               = var.citrix_published_desktop_name
  desktop_restricted_access_allow_list = var.citrix_desktop_restricted_access_allow_list
  autoscale_enabled                    = var.citrix_autoscale_enabled
  autoscale_timezone                   = var.citrix_autoscale_timezone

  # Template Spec is created out-of-band (az CLI, not Terraform-managed) -
  # see modules/citrix/README.md. No Cloud Connector VMs in this environment
  # - VDAs register with Citrix Cloud directly via Rendezvous Protocol, and
  # the Azure hosting connection below talks to Azure's ARM API directly, so
  # MCS provisioning never needed one either.
  machine_profile_template_spec_name    = var.machine_profile_template_spec_name
  machine_profile_template_spec_version = var.machine_profile_template_spec_version
  machine_profile_resource_group_name   = azurerm_resource_group.this.name
}

module "github_runner" {
  source = "../../modules/github-runner"

  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  subnet_id            = module.network.vda_subnet_id
  name                 = var.github_runner_name
  vm_size              = var.github_runner_vm_size
  admin_username       = var.github_runner_admin_username
  admin_ssh_public_key = var.github_runner_admin_ssh_public_key
  tags                 = var.tags
}
