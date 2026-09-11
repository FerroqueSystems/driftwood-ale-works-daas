# Argument names below are verified against the citrix/citrix provider docs
# (github.com/citrix/terraform-provider-citrix) as of this writing. The provider
# evolves quickly - re-check `terraform providers schema -json` after upgrading.

# Groups this environment's machine catalogs and delivery groups under one
# admin folder in Citrix Studio/Web Studio, matching how other
# environments/customers already organize theirs (a single folder can hold
# both object types at once via its `type` set).
resource "citrix_admin_folder" "this" {
  name = var.admin_folder_name
  type = ["ContainsMachineCatalogs", "ContainsDeliveryGroups"]
}

resource "citrix_cloud_resource_location" "this" {
  name = var.resource_location_name
}

resource "citrix_zone" "this" {
  description          = var.zone_description
  resource_location_id = citrix_cloud_resource_location.this.id
}

resource "citrix_azure_hypervisor" "this" {
  name                = var.hypervisor_name
  zone                = citrix_zone.this.id
  active_directory_id = var.active_directory_id
  subscription_id     = var.subscription_id
  application_id      = var.application_id
  application_secret  = var.application_secret
}

resource "citrix_azure_hypervisor_resource_pool" "this" {
  name                           = var.resource_pool_name
  hypervisor                     = citrix_azure_hypervisor.this.id
  region                         = var.region
  virtual_network                = var.vnet_name
  virtual_network_resource_group = var.vnet_resource_group_name
  subnets                        = var.subnets
}

# --- Golden image versioning, machine catalogs, delivery groups ---
# One long-lived image definition wraps the Azure Compute Gallery image
# definition Packer publishes into (see ../../modules/image-gallery and
# ../../packer) - shared by every environment, since there's one golden-image
# lineage feeding dev/test/prod alike. Each monthly build gets its own
# citrix_image_version (deduped across environments, see
# local.unique_image_versions) and one citrix_machine_catalog per environment
# that has staged it (see local.flattened_catalogs), keyed by the "YYMM-N"
# label in var.catalog_rotation.

locals {
  # Flatten var.catalog_rotation (env -> label -> catalog) down to a single
  # map keyed "<env>-<label>" (e.g. "dev-2601-1") for citrix_machine_catalog's
  # for_each - each environment's catalogs are wholly independent Citrix
  # objects even when two environments happen to be staged on the same build
  # label.
  flattened_catalogs = merge([
    for env, labels in var.catalog_rotation : {
      for label, v in labels : "${env}-${label}" => merge(v, {
        env   = env
        label = label
      })
    }
  ]...)

  # Dedupe across environments down to unique build labels for
  # citrix_image_version's for_each, keyed by label only - the image version
  # itself is environment-agnostic (one shared Packer build feeds
  # dev/test/prod alike), so the same label staged in all three must not try
  # to create three citrix_image_version resources for the same underlying
  # Azure Compute Gallery image version. Relies on every environment agreeing
  # on gallery_image_version for a given label, enforced by var.catalog_rotation's
  # validation block.
  unique_image_versions = merge([
    for env, labels in var.catalog_rotation : {
      for label, v in labels : label => v.gallery_image_version
    }
  ]...)
}

# One resource group per machine catalog build (keyed the same way as
# citrix_machine_catalog below, "<env>-<label>") so MCS-provisioned VDA
# VMs/NICs/disks from different environments/rotation generations never land
# in the same resource group - keeps cutover/decommission cycles from
# crossing over each other. Keyed off each.key (the for_each identity itself,
# structurally unique) rather than catalog_name (only conventionally unique,
# enforced by Citrix's API, not Terraform).
resource "azurerm_resource_group" "vda" {
  for_each = local.flattened_catalogs

  name     = "rg-vda-${each.key}"
  location = var.location
  tags     = var.tags
}

resource "citrix_image_definition" "vda" {
  name                     = var.image_definition_name
  hypervisor               = citrix_azure_hypervisor.this.id
  hypervisor_resource_pool = citrix_azure_hypervisor_resource_pool.this.id
  os_type                  = var.os_type
  session_support          = var.session_support

  azure_image_definition = {
    use_image_gallery  = true
    image_gallery_name = var.image_gallery_name
    resource_group     = var.image_gallery_resource_group_name
  }
}

resource "citrix_image_version" "vda" {
  for_each = local.unique_image_versions

  image_definition         = citrix_image_definition.vda.id
  hypervisor               = citrix_azure_hypervisor.this.id
  hypervisor_resource_pool = citrix_azure_hypervisor_resource_pool.this.id
  description              = "Golden image build ${each.key}"

  azure_image_specs = {
    resource_group   = var.image_gallery_resource_group_name
    service_offering = var.service_offering
    storage_type     = var.storage_type

    gallery_image = {
      gallery    = var.image_gallery_name
      definition = var.image_definition_name
      version    = each.value
    }
  }
}

resource "citrix_machine_catalog" "vda" {
  for_each = local.flattened_catalogs

  name                        = each.value.catalog_name
  description                 = "Golden image build ${each.value.label} (${each.value.env})"
  zone                        = citrix_zone.this.id
  allocation_type             = var.allocation_type
  session_support             = var.session_support
  provisioning_type           = "MCS"
  machine_catalog_folder_path = citrix_admin_folder.this.path

  provisioning_scheme = {
    hypervisor               = citrix_azure_hypervisor.this.id
    hypervisor_resource_pool = citrix_azure_hypervisor_resource_pool.this.id
    identity_type            = "ActiveDirectory"
    number_of_total_machines = each.value.total_machines

    machine_account_creation_rules = {
      naming_scheme      = each.value.machine_naming_scheme
      naming_scheme_type = "Numeric"
    }

    # Required for identity_type = "ActiveDirectory" - the domain, target OU
    # for computer accounts, and the service account MCS uses to create/
    # manage them (created by modules/domain-controllers; added to Domain
    # Admins there as a deliberate demo-only simplification over Citrix's
    # documented least-privilege OU delegation - see that module's README).
    machine_domain_identity = {
      domain                   = var.active_directory_domain_fqdn
      domain_ou                = var.active_directory_vda_ou_dn
      service_account          = var.active_directory_service_account_name
      service_account_password = var.active_directory_service_account_password
    }

    # Optional for identity_type = "ActiveDirectory" (MCS falls back to a
    # single NIC on the resource pool's default network if omitted) - kept
    # explicit anyway since it's already correct and harmless.
    network_mapping = [
      {
        network        = var.subnets[0]
        network_device = "0"
      }
    ]

    azure_machine_config = {
      service_offering = var.service_offering
      storage_type     = var.storage_type

      # Without this, MCS auto-creates its own resource group per
      # hypervisor connection ("citrix-xd-<connection-guid>-<random>") to
      # hold provisioned VMs/NICs/disks instead of using an existing one.
      # Dedicated per catalog build (azurerm_resource_group.vda above, keyed
      # the same way) rather than one shared resource group, so different
      # environments/rotation generations' VDA resources never cross over.
      vda_resource_group = azurerm_resource_group.vda[each.key].name

      # No machine_profile here - that's only required when identity_type
      # is "AzureAD" (or provisioning_type is "PVSStreaming", not
      # applicable here), confirmed against the citrix/citrix provider's
      # schema. Dropping it also drops the out-of-band Template Spec
      # creation step (az ts create) this repo previously required.
      azure_master_image = {
        resource_group = var.image_gallery_resource_group_name
        gallery_image = {
          gallery    = var.image_gallery_name
          definition = var.image_definition_name
          version    = each.value.gallery_image_version
        }
      }
    }
  }
}

resource "citrix_delivery_group" "vda" {
  for_each = var.delivery_groups

  name                       = each.value.name
  delivery_group_folder_path = citrix_admin_folder.this.path

  # Citrix rejects machine_count = 0 on *any* entry in
  # associated_machine_catalogs, not just a newly-added one - a catalog being
  # drained for decommission (machine_count dropped to 0 at cutover) has to
  # be removed from this list entirely, not kept in it at zero. Scoped to
  # only this environment's slice of local.flattened_catalogs - dev/test/prod
  # each own a disjoint set of machine catalogs.
  associated_machine_catalogs = [
    for key, v in local.flattened_catalogs : {
      machine_catalog = citrix_machine_catalog.vda[key].id
      machine_count   = v.machine_count
    }
    if v.env == each.key && v.machine_count > 0
  ]

  desktops = [
    {
      published_name = each.value.published_desktop_name
      enabled        = true
      # Required by Citrix whenever the associated machine catalog uses
      # Random allocation type (var.allocation_type here) - lets a user
      # reconnect to their existing session from a different endpoint,
      # which matters since Random allocation doesn't pin them to one
      # machine.
      enable_session_roaming = true
      restricted_access_users = {
        allow_list = each.value.desktop_restricted_access_allow_list
      }
    }
  ]

  autoscale_settings = {
    autoscale_enabled = each.value.autoscale_enabled
    timezone          = each.value.autoscale_timezone

    # Per-environment power time schemes (see var.delivery_groups) - Citrix
    # rejects an explicit pool_size = 0 entry ("value must be at least 1"),
    # same "no zero" rule as associated_machine_catalogs' machine_count just
    # surfacing in a different field, so "nothing powered on" outside a
    # scheme's time ranges is expressed by omitting that time range entirely
    # rather than listing it at 0.
    power_time_schemes = each.value.power_time_schemes
  }
}
