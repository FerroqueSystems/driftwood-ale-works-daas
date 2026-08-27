# Environment-level input variables for Citrix deployment

variable "location" {
  description = "Azure location for Citrix resources"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Resource group name for the Citrix environment"
  type        = string
}

variable "tags" {
  description = "Tags applied to Azure resources in this environment"
  type        = map(string)
  default     = {}
}

# --- Networking ---

variable "vnet_name" {
  description = "Name of the virtual network for the Citrix resource location"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
}

variable "vda_subnet_address_prefixes" {
  description = "Address prefixes for the subnet hosting VDAs"
  type        = list(string)
}

# --- Azure AD hosting connection identity (the "application piece" from Azure) ---

variable "hosting_connection_app_name" {
  description = "Display name for the Azure AD app registration Citrix uses as its hosting connection service principal"
  type        = string
  default     = "driftwood-citrix-daas-hosting-connection"
}

variable "azure_subscription_id" {
  description = "Azure subscription ID that hosts the Citrix resource location"
  type        = string
}

variable "azure_tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

# --- Citrix Cloud (the authentication portion from Citrix Cloud) ---

variable "citrix_customer_id" {
  description = "Citrix Cloud customer ID"
  type        = string
}

variable "citrix_client_id" {
  description = "Citrix Cloud API key client ID"
  type        = string
}

variable "citrix_environment" {
  description = "Citrix Cloud environment (Production, Staging, Japan, JapanStaging, Gov, GovStaging)"
  type        = string
  default     = "Production"
}

variable "citrix_resource_location_name" {
  description = "Name of the Citrix Cloud resource location for this environment"
  type        = string
}

variable "citrix_zone_description" {
  description = "Description for the Citrix DaaS zone"
  type        = string
  default     = ""
}

variable "citrix_hypervisor_name" {
  description = "Name of the Azure hosting connection in Citrix DaaS"
  type        = string
}

variable "citrix_resource_pool_name" {
  description = "Name of the Citrix hypervisor resource pool"
  type        = string
}

# --- Golden image versioning / machine catalog rotation ---
# See ../../modules/citrix/README.md for the monthly "YYMM-N" rotation
# convention this drives. No hard entry-count limit - see
# scripts/rotate_image_versions.py's --max-entries.

variable "image_versions" {
  description = "Golden image builds to run as machine catalogs, keyed by the \"YYMM-N\" build label (e.g. \"2607-1\")"
  type = map(object({
    gallery_image_version = string
    total_machines        = number
    machine_count         = number
    machine_naming_scheme = string
    catalog_name          = string
  }))
}

variable "citrix_catalog_name_prefix" {
  description = "Prefix for newly-staged machine catalog names (each is named \"<prefix>-<build label>\") - NOT passed into module.citrix (catalog_name is per-build, recorded in image_versions/rotation.auto.tfvars.json, so changing this doesn't rename already-built catalogs). Read from ci.auto.tfvars.json by citrix-image-rotation.yml's build job to seed new labels."
  type        = string
  default     = "driftwood-win11-vda"
}

variable "citrix_delivery_group_name" {
  description = "Name of the Citrix delivery group that desktops are published through"
  type        = string
  default     = "driftwood-win11-desktops"
}

variable "citrix_published_desktop_name" {
  description = "Display name of the published desktop shown to end users in Citrix Workspace"
  type        = string
  default     = "Windows 11 Entra Desktop"
}

variable "citrix_desktop_restricted_access_allow_list" {
  description = "Users/groups allowed to see the published desktop, in Citrix's format (e.g. \"OID:/azuread/<object_id>\" for an Entra ID group)"
  type        = list(string)
}

variable "citrix_autoscale_enabled" {
  description = "Whether autoscale is enabled for the delivery group"
  type        = bool
  default     = true
}

variable "citrix_autoscale_timezone" {
  description = "Windows time zone ID (e.g. \"Eastern Standard Time\") the delivery group's autoscale power time schemes run in"
  type        = string
}

variable "citrix_allocation_type" {
  description = "MCS allocation type for the machine catalogs"
  type        = string
  default     = "Random"
}

variable "citrix_machine_naming_scheme" {
  description = "MCS machine account naming scheme template (numeric suffix denoted by ##) for newly-staged builds - NOT passed into module.citrix (naming_scheme is per-build, recorded in image_versions/rotation.auto.tfvars.json, so changing this doesn't affect already-built catalogs). Read from ci.auto.tfvars.json by citrix-image-rotation.yml's build job to seed new labels."
  type        = string
  default     = "driftwood-vda-##"
}

variable "citrix_vda_service_offering" {
  description = "Azure VM SKU used when MCS provisions VDA machines"
  type        = string
}

variable "citrix_vda_storage_type" {
  description = "Azure storage account type for provisioned VDA disks (Standard_LRS, StandardSSD_LRS, Premium_LRS)"
  type        = string
  default     = "StandardSSD_LRS"
}

# --- Machine profile (required for AzureAD-identity catalogs, see modules/citrix/README.md) ---

variable "machine_profile_template_spec_name" {
  description = "Name of the Azure Template Spec used as the Citrix machine profile - created out-of-band via az CLI, not Terraform-managed"
  type        = string
}

variable "machine_profile_template_spec_version" {
  description = "Version of the machine profile Template Spec to use"
  type        = string
}

# --- Self-hosted GitHub Actions runner (for citrix-image-rotation.yml) ---

variable "github_runner_name" {
  description = "Name of the self-hosted GitHub Actions runner VM"
  type        = string
  default     = "driftwood-gh-runner"
}

variable "github_runner_vm_size" {
  description = "Azure VM size for the self-hosted runner VM"
  type        = string
  default     = "Standard_B2s"
}

variable "github_runner_admin_username" {
  description = "Admin username for the self-hosted runner VM"
  type        = string
  default     = "ghrunner"
}

variable "github_runner_admin_ssh_public_key" {
  description = "SSH public key for the self-hosted runner VM's admin user (key-based auth only, no password)"
  type        = string
}

# --- Golden image pipeline (Packer publishes into this gallery, see ../../packer) ---

variable "gallery_name" {
  description = "Name of the Azure Shared Image Gallery for VDA master images"
  type        = string
}

variable "image_definition_name" {
  description = "Name of the VDA image definition within the gallery"
  type        = string
}

variable "image_sku" {
  description = "SKU value for the VDA image definition identifier"
  type        = string
}

# --- Image build artifact storage (Citrix VDA installer, Citrix Optimizer zip) ---

variable "artifact_storage_account_name" {
  description = "Globally-unique name for the private storage account holding Packer image build artifacts (lowercase letters/numbers only, 3-24 characters)"
  type        = string
}

variable "artifact_storage_container_name" {
  description = "Name of the private blob container holding Packer image build artifacts"
  type        = string
  default     = "image-build-artifacts"
}
