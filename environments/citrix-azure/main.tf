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

  # Active Directory distinguished names, computed once from simple name
  # variables and reused everywhere an OU/domain DN is needed
  # (module.cloud_connectors, module.citrix) - modules/domain-controllers'
  # own scripts compute these independently at runtime (they don't consume
  # this local), so both sides just need to agree on the same base/vda/
  # connector OU *names*, not share this computed value directly.
  ad_domain_dn       = join(",", [for part in split(".", var.active_directory_domain_fqdn) : "DC=${part}"])
  ad_base_ou_dn      = "OU=${var.active_directory_base_ou_name},${local.ad_domain_dn}"
  ad_vda_ou_dn       = "OU=${var.active_directory_vda_ou_name},${local.ad_base_ou_dn}"
  ad_connector_ou_dn = "OU=${var.active_directory_connector_ou_name},${local.ad_base_ou_dn}"

  # Computed independently here (not read from module.domain_controllers'
  # own identical computation) specifically to avoid a circular module
  # dependency: module.network needs these for its vnet dns_servers, but
  # module.domain_controllers needs module.network.vda_subnet_id for its
  # VMs' subnet - a real cycle if either module fed the other this value
  # instead of both deriving it from the same plain input independently.
  dc_private_ips = [
    cidrhost(var.vda_subnet_address_prefixes[0], 4),
    cidrhost(var.vda_subnet_address_prefixes[0], 5),
  ]
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

  # Points every NIC without its own override (future Citrix MCS-provisioned
  # VDAs, in particular - no per-catalog DNS override exists in the
  # citrix/citrix provider) at the two domain controllers.
  dns_servers = local.dc_private_ips

  # Temporary, source-IP-scoped inbound SSH allow rule for one-time GitHub
  # runner registration (see module.github_runner below and
  # bootstrap-github-runner-commands.txt) - null (no rule) unless explicitly
  # enabled.
  admin_ssh_source_cidr = var.enable_runner_temporary_ssh_access ? var.admin_source_ip_cidr : null
}

module "domain_controllers" {
  source = "../../modules/domain-controllers"

  resource_group_name          = azurerm_resource_group.this.name
  location                     = azurerm_resource_group.this.location
  subnet_id                    = module.network.vda_subnet_id
  subnet_address_prefix        = var.vda_subnet_address_prefixes[0]
  admin_username               = var.domain_controller_admin_username
  admin_password               = var.domain_controller_admin_password
  domain_fqdn                  = var.active_directory_domain_fqdn
  domain_netbios_name          = var.active_directory_domain_netbios_name
  safe_mode_password           = var.active_directory_safe_mode_password
  service_account_name         = var.active_directory_service_account_name
  service_account_password     = var.active_directory_service_account_password
  base_ou_name                 = var.active_directory_base_ou_name
  vda_ou_name                  = var.active_directory_vda_ou_name
  connector_ou_name            = var.active_directory_connector_ou_name
  dev_desktop_group_name       = var.active_directory_dev_desktop_group_name
  test_desktop_group_name      = var.active_directory_test_desktop_group_name
  prod_desktop_group_name      = var.active_directory_prod_desktop_group_name
  scripts_storage_account_name = var.domain_controller_scripts_storage_account_name
  tags                         = var.tags

  enable_scheduled_shutdown   = var.enable_scheduled_shutdown
  scheduled_shutdown_time     = var.scheduled_shutdown_time
  scheduled_shutdown_timezone = var.scheduled_shutdown_timezone
}

module "cloud_connectors" {
  source = "../../modules/cloud-connectors"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = module.network.vda_subnet_id
  admin_username      = var.cloud_connector_admin_username
  admin_password      = var.cloud_connector_admin_password
  tags                = var.tags

  dns_servers                   = local.dc_private_ips
  domain_fqdn                   = var.active_directory_domain_fqdn
  domain_netbios_name           = var.active_directory_domain_netbios_name
  connector_ou_dn               = local.ad_connector_ou_dn
  service_account_name          = var.active_directory_service_account_name
  service_account_password      = var.active_directory_service_account_password
  citrix_customer_id            = var.citrix_customer_id
  cloud_connector_client_id     = var.cloud_connector_client_id
  cloud_connector_client_secret = var.cloud_connector_client_secret
  citrix_resource_location_id   = module.citrix.resource_location_id
  cloud_connector_installer_url = var.cloud_connector_installer_url
  scripts_storage_account_name  = var.cloud_connector_scripts_storage_account_name

  enable_scheduled_shutdown   = var.enable_scheduled_shutdown
  scheduled_shutdown_time     = var.scheduled_shutdown_time
  scheduled_shutdown_timezone = var.scheduled_shutdown_timezone

  depends_on = [module.domain_controllers]
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
  location                 = var.location
  tags                     = var.tags
  vnet_name                = module.network.vnet_name
  vnet_resource_group_name = azurerm_resource_group.this.name
  subnets                  = [module.network.vda_subnet_name]

  image_gallery_name                = module.image_gallery.gallery_name
  image_gallery_resource_group_name = azurerm_resource_group.this.name
  image_definition_name             = var.image_definition_name
  catalog_rotation                  = var.catalog_rotation

  delivery_groups  = var.delivery_groups
  allocation_type  = var.citrix_allocation_type
  service_offering = var.citrix_vda_service_offering
  storage_type     = var.citrix_vda_storage_type

  active_directory_domain_fqdn              = var.active_directory_domain_fqdn
  active_directory_vda_ou_dn                = local.ad_vda_ou_dn
  active_directory_service_account_name     = var.active_directory_service_account_name
  active_directory_service_account_password = var.active_directory_service_account_password

  # module.domain_controllers: no natural attribute dependency exists (the
  # AD variables above are plain strings/locals, not domain_controllers
  # outputs), so without this explicit depends_on, Terraform would happily
  # create machine catalogs in full parallel with the domain controllers -
  # guaranteed to fail outright (the domain doesn't exist yet), not just a
  # soft race. Safe to add (no cycle - domain_controllers doesn't depend on
  # this module).
  #
  # No depends_on module.cloud_connectors here - module.cloud_connectors
  # already depends on this module's resource_location_id output, so adding
  # a module-level depends_on back the other way would be a circular
  # dependency. Citrix requires Cloud Connectors present in the zone for
  # AD-domain-joined machine catalogs to actually provision successfully,
  # but that's a Citrix Cloud backend requirement, not something Terraform's
  # citrix_machine_catalog create call blocks on - see
  # modules/cloud-connectors/README.md's "First-apply race" note for why a
  # transient error on the very first from-scratch apply is expected and
  # safe to retry.
  depends_on = [module.domain_controllers]
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

  # See module.network's admin_ssh_source_cidr above - both are driven off
  # the same enable_runner_temporary_ssh_access flag.
  enable_temporary_public_access = var.enable_runner_temporary_ssh_access

  enable_scheduled_shutdown   = var.enable_scheduled_shutdown
  scheduled_shutdown_time     = var.scheduled_shutdown_time
  scheduled_shutdown_timezone = var.scheduled_shutdown_timezone
}
