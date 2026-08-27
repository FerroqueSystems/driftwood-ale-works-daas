# Argument names below are verified against the citrix/citrix provider docs
# (github.com/citrix/terraform-provider-citrix) as of this writing. The provider
# evolves quickly - re-check `terraform providers schema -json` after upgrading.

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

# --- Golden image versioning, machine catalogs, delivery group ---
# One long-lived image definition wraps the Azure Compute Gallery image
# definition Packer publishes into (see ../../modules/image-gallery and
# ../../packer). Each monthly build gets its own citrix_image_version +
# citrix_machine_catalog, keyed by the "YYMM-N" label in var.image_versions.

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
  for_each = var.image_versions

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
      version    = each.value.gallery_image_version
    }
  }
}

resource "citrix_machine_catalog" "vda" {
  for_each = var.image_versions

  name              = each.value.catalog_name
  description       = "Golden image build ${each.key}"
  zone              = citrix_zone.this.id
  allocation_type   = var.allocation_type
  session_support   = var.session_support
  provisioning_type = "MCS"

  provisioning_scheme = {
    hypervisor               = citrix_azure_hypervisor.this.id
    hypervisor_resource_pool = citrix_azure_hypervisor_resource_pool.this.id
    identity_type            = "AzureAD"
    number_of_total_machines = each.value.total_machines

    machine_account_creation_rules = {
      naming_scheme      = each.value.machine_naming_scheme
      naming_scheme_type = "Numeric"
    }

    # Required when identity_type = "AzureAD" - Azure AD-joined machines need
    # an explicit NIC-to-subnet mapping.
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
      vda_resource_group = var.vda_resource_group_name

      # Required when identity_type = "AzureAD" - a Template Spec Citrix uses
      # to derive machine defaults (size, boot diagnostics, OS disk caching,
      # accelerated networking). Must be a Template Spec, not a VM reference
      # - a VM-based machine_profile fails validation with a confusing
      # "machine_profile cannot be specified when using prepared image
      # without a machine profile" error (citrix/terraform-provider-citrix
      # v1.0.38). See modules/citrix/README.md for how the template spec is
      # created and what it must (and must not) contain.
      machine_profile = {
        machine_profile_template_spec_name    = var.machine_profile_template_spec_name
        machine_profile_template_spec_version = var.machine_profile_template_spec_version
        machine_profile_resource_group        = var.machine_profile_resource_group_name
      }

      # Deliberately azure_master_image (direct gallery/definition/version
      # reference), not prepared_image (which references citrix_image_version
      # above by ID) - prepared_image + machine_profile + identity_type
      # "AzureAD" hits the same validation error mentioned above regardless
      # of machine_profile's form. citrix_image_version above still gets
      # created for Citrix Cloud's Image Management visibility/tracking, it's
      # just not what the machine catalog itself references.
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
  name = var.delivery_group_name

  # Citrix rejects machine_count = 0 on *any* entry in
  # associated_machine_catalogs, not just a newly-added one - a catalog being
  # drained for decommission (machine_count dropped to 0 at cutover) has to
  # be removed from this list entirely, not kept in it at zero.
  associated_machine_catalogs = [
    for label, v in var.image_versions : {
      machine_catalog = citrix_machine_catalog.vda[label].id
      machine_count   = v.machine_count
    }
    if v.machine_count > 0
  ]

  desktops = [
    {
      published_name = var.published_desktop_name
      enabled        = true
      # Required by Citrix whenever the associated machine catalog uses
      # Random allocation type (var.allocation_type here) - lets a user
      # reconnect to their existing session from a different endpoint,
      # which matters since Random allocation doesn't pin them to one
      # machine.
      enable_session_roaming = true
      restricted_access_users = {
        allow_list = var.desktop_restricted_access_allow_list
      }
    }
  ]

  autoscale_settings = {
    autoscale_enabled = var.autoscale_enabled
    timezone          = var.autoscale_timezone

    # Weekday ramp: 20% powered on 08:00-10:00, 10% 10:00-17:00, nothing
    # powered on outside that window (including weekends, which aren't
    # covered by any power_time_scheme). Citrix rejects an explicit
    # pool_size = 0 entry ("value must be at least 1") - same "no zero"
    # rule as associated_machine_catalogs' machine_count, just surfacing in
    # a different field. So "nothing powered on" is expressed by omitting
    # the time range entirely rather than listing it at 0.
    power_time_schemes = [
      {
        days_of_week          = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        display_name          = "Weekday business hours"
        peak_time_ranges      = ["08:00-17:00"]
        pool_using_percentage = true
        pool_size_schedules = [
          { time_range = "08:00-10:00", pool_size = 20 },
          { time_range = "10:00-17:00", pool_size = 10 },
        ]
      }
    ]
  }
}
