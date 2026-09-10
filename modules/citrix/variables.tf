variable "resource_location_name" {
  description = "Name of the Citrix Cloud resource location for this Azure environment"
  type        = string
}

variable "zone_description" {
  description = "Description for the Citrix DaaS zone associated with the resource location"
  type        = string
  default     = ""
}

variable "hypervisor_name" {
  description = "Name of the Azure hosting connection in Citrix DaaS"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID for the hosting connection"
  type        = string
}

variable "active_directory_id" {
  description = "Azure AD tenant ID for the hosting connection"
  type        = string
}

variable "application_id" {
  description = "Client ID of the Azure AD app registration used for the hosting connection (see modules/identity)"
  type        = string
}

variable "application_secret" {
  description = "Client secret of the Azure AD app registration used for the hosting connection"
  type        = string
  sensitive   = true
}

variable "resource_pool_name" {
  description = "Name of the Citrix hypervisor resource pool"
  type        = string
}

variable "region" {
  description = "Azure region where the virtual network sits (e.g. \"East US\") - Citrix's human-readable display form, used only for the hypervisor resource pool. Distinct from var.location below (the raw Azure location slug used for azurerm resources this module creates)."
  type        = string
}

variable "location" {
  description = "Azure location slug (e.g. \"eastus\") this module's azurerm resources (the per-catalog VDA resource groups) are created in - distinct from var.region above"
  type        = string
}

variable "tags" {
  description = "Tags applied to azurerm resources this module creates"
  type        = map(string)
  default     = {}
}

variable "vnet_name" {
  description = "Name of the cloud virtual network from modules/network"
  type        = string
}

variable "vnet_resource_group_name" {
  description = "Name of the resource group where the virtual network resides"
  type        = string
}

variable "subnets" {
  description = "Subnet names within the virtual network available to the resource pool for VDA placement"
  type        = list(string)
}

# --- Golden image versioning (Citrix Image Management Service) ---
# See environments/citrix-azure/README.md for the monthly rotation convention
# this is built around - no technical limit on how many entries can coexist
# per environment in var.catalog_rotation; scripts/rotate_image_versions.py
# applies a soft, tunable cap per environment when staging new labels (see
# modules/citrix/README.md).

variable "image_gallery_name" {
  description = "Name of the existing Azure Shared Image Gallery Packer publishes VDA master images into (see modules/image-gallery)"
  type        = string
}

variable "image_gallery_resource_group_name" {
  description = "Name of the resource group that owns the Azure Shared Image Gallery"
  type        = string
}


variable "image_definition_name" {
  description = "Name of the Azure image definition within the gallery (see modules/image-gallery) - reused as the Citrix image definition's display name"
  type        = string
}

variable "os_type" {
  description = "OS type of the VDA master image"
  type        = string
  default     = "Windows"
}

variable "session_support" {
  description = "Session support for the image/machine catalog - SingleSession for Windows 11 VDI, MultiSession for Windows Server RDSH"
  type        = string
  default     = "SingleSession"
}

variable "catalog_rotation" {
  description = "Per-environment golden image build/catalog rotation state, outer-keyed by environment (\"dev\"/\"test\"/\"prod\"), inner-keyed by the \"YYMM-N\" build label (e.g. \"2607-1\"). CI-managed - sourced from rotation.auto.tfvars.json (Terraform auto-loads *.auto.tfvars.json), not terraform.tfvars, since Terraform replaces (not deep-merges) a variable's value across auto-loaded tfvars files. Each environment's rotation state is fully independent (dev can be on a different label than prod) even though the same label means the same gallery_image_version everywhere - one shared Packer build feeds dev/test/prod alike; each environment cuts over to it on its own schedule. No hard limit on entry count per environment - scripts/rotate_image_versions.py's build command applies a soft, tunable cap when staging new labels."
  type = map(map(object({
    gallery_image_version = string # Azure Compute Gallery numeric version this label maps to, e.g. "2607.1.0" - identical across every environment that has this label staged (enforced by the validation block below)
    total_machines        = number # machines provisioned in this catalog
    machine_count         = number # of those machines, how many are assigned to this environment's delivery group (0 while staged, ramped up during cutover, dropped to 0 before decommission)
    machine_naming_scheme = string # MCS machine account naming scheme template (numeric suffix denoted by ##) - fixed per (environment, build label) pair at creation time, never changed retroactively (changing an existing catalog's naming_scheme forces it to be replaced)
    catalog_name          = string # full citrix_machine_catalog name - also fixed per (environment, build label) pair at creation time, never changed retroactively (changing an existing catalog's name forces it to be replaced)
  })))

  validation {
    condition = alltrue([
      for label in distinct(flatten([for env, labels in var.catalog_rotation : keys(labels)])) : (
        length(distinct([
          for env, labels in var.catalog_rotation : labels[label].gallery_image_version
          if contains(keys(labels), label)
        ])) <= 1
      )
    ])
    error_message = "Every environment that stages the same \"YYMM-N\" build label must agree on gallery_image_version - it's one shared golden-image lineage; two environments can't disagree on what that label points to (citrix_image_version is deduped across environments in main.tf and relies on this)."
  }
}

variable "allocation_type" {
  description = "MCS allocation type for the machine catalogs"
  type        = string
  default     = "Random"
}

variable "service_offering" {
  description = "Azure VM SKU used when MCS provisions VDA machines"
  type        = string
}

variable "storage_type" {
  description = "Azure storage account type for provisioned VDA disks (Standard_LRS, StandardSSD_LRS, Premium_LRS)"
  type        = string
  default     = "StandardSSD_LRS"
}

variable "delivery_groups" {
  description = "Static per-environment delivery group config, keyed by environment (\"dev\"/\"test\"/\"prod\") - name, published desktop, access allow-list, autoscale settings, and the catalog-naming conventions the rotation workflow seeds new builds with. Rarely changes, human-edited (terraform.tfvars), unlike var.catalog_rotation."
  type = map(object({
    name                                 = string       # Citrix delivery group name
    published_desktop_name               = string       # display name of the published desktop shown to end users in Citrix Workspace
    desktop_restricted_access_allow_list = list(string) # users/groups allowed to see the published desktop, in traditional AD form ("<NETBIOS>\<GroupName>", e.g. "DRIFTWOOD\Driftwood Dev Desktop Users" - the AD groups modules/domain-controllers creates)
    autoscale_enabled                    = bool
    autoscale_timezone                   = string # Windows time zone ID (e.g. "Eastern Standard Time") the delivery group's autoscale power time schemes run in
    power_time_schemes = list(object({
      days_of_week          = list(string)
      display_name          = string
      peak_time_ranges      = list(string)
      pool_using_percentage = bool
      pool_size_schedules = list(object({
        time_range = string
        pool_size  = number
      }))
    }))
    catalog_name_prefix   = string # newly-staged catalogs in this environment are named "<prefix>-<build label>" - NOT used by resources in this module directly (catalog_name is per-build, recorded in catalog_rotation), read by citrix-image-rotation.yml's build job to seed new labels
    machine_naming_scheme = string # MCS machine account naming scheme template (numeric suffix denoted by ##) for newly-staged builds in this environment - NOT used by resources in this module directly (naming_scheme is per-build, recorded in catalog_rotation), read by citrix-image-rotation.yml's build job to seed new labels
  }))
}

# --- Active Directory (identity_type = "ActiveDirectory" machine catalogs) ---
# No machine_profile/Template Spec here - that's only required for AzureAD
# identity (or PVSStreaming), not applicable to this AD-domain-joined
# design. See modules/domain-controllers for where the domain/service
# account are actually created.

variable "active_directory_domain_fqdn" {
  description = "FQDN of the AD domain VDAs are joined to (e.g. \"driftwood.local\")"
  type        = string
}

variable "active_directory_vda_ou_dn" {
  description = "Distinguished name of the OU VDA computer accounts are created into (e.g. \"OU=VDAs,OU=Driftwood,DC=driftwood,DC=local\")"
  type        = string
}

variable "active_directory_service_account_name" {
  description = "SAM account name of the domain service account MCS uses to create/manage VDA computer accounts (created by modules/domain-controllers)"
  type        = string
}

variable "active_directory_service_account_password" {
  description = "Password for var.active_directory_service_account_name"
  type        = string
  sensitive   = true
}

