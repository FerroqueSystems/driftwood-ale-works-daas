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
  description = "Azure region where the virtual network sits (e.g. \"East US\")"
  type        = string
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
# this is built around - no technical limit on how many var.image_versions
# entries can coexist; scripts/rotate_image_versions.py applies a soft,
# tunable cap when staging new labels (see modules/citrix/README.md).

variable "image_gallery_name" {
  description = "Name of the existing Azure Shared Image Gallery Packer publishes VDA master images into (see modules/image-gallery)"
  type        = string
}

variable "image_gallery_resource_group_name" {
  description = "Name of the resource group that owns the Azure Shared Image Gallery"
  type        = string
}

variable "vda_resource_group_name" {
  description = "Existing resource group MCS places provisioned VDA VMs/NICs/disks into - without this, MCS auto-creates its own per-hypervisor-connection resource group instead"
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

variable "image_versions" {
  description = "Golden image builds to run as machine catalogs, keyed by the \"YYMM-N\" build label (e.g. \"2607-1\"). No hard limit on entry count - scripts/rotate_image_versions.py's build command applies a soft, tunable cap when staging new labels."
  type = map(object({
    gallery_image_version = string # Azure Compute Gallery numeric version this label maps to, e.g. "2607.1.0"
    total_machines        = number # machines provisioned in this catalog
    machine_count         = number # of those machines, how many are assigned to the delivery group (0 while staged, ramped up during cutover, dropped to 0 before decommission)
    machine_naming_scheme = string # MCS machine account naming scheme template (numeric suffix denoted by ##) - fixed per build label at creation time, never changed retroactively (changing an existing catalog's naming_scheme forces it to be replaced)
    catalog_name          = string # full citrix_machine_catalog name - also fixed per build label at creation time, never changed retroactively (changing an existing catalog's name forces it to be replaced)
  }))
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

variable "delivery_group_name" {
  description = "Name of the Citrix delivery group that desktops are published through"
  type        = string
  default     = "driftwood-win11-desktops"
}

variable "published_desktop_name" {
  description = "Display name of the published desktop shown to end users in Citrix Workspace"
  type        = string
  default     = "Windows 11 Entra Desktop"
}

variable "desktop_restricted_access_allow_list" {
  description = "Users/groups allowed to see the published desktop, in Citrix's format (\"OID:/azuread/<object_id>\" for an Entra ID group, \"user@domain.com\" for a UPN, etc.) - required for this Entra ID-joined (no traditional AD) environment since there's no SID/SAM-account-name form available"
  type        = list(string)
}

variable "autoscale_enabled" {
  description = "Whether autoscale is enabled for the delivery group"
  type        = bool
  default     = true
}

variable "autoscale_timezone" {
  description = "Windows time zone ID (e.g. \"Eastern Standard Time\") the delivery group's autoscale power time schemes run in"
  type        = string
}

variable "machine_profile_template_spec_name" {
  description = "Name of the Azure Template Spec Citrix uses to derive machine defaults (size, tags, accelerated networking, AZ) for AzureAD-identity catalogs with a prepared_image - see modules/citrix/README.md for how it's created"
  type        = string
}

variable "machine_profile_template_spec_version" {
  description = "Version of the machine profile Template Spec to use"
  type        = string
}

variable "machine_profile_resource_group_name" {
  description = "Resource group of the machine profile Template Spec"
  type        = string
}

