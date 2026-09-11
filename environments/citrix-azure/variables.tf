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

# --- Scheduled shutdown (this is a temporary demo environment, torn down
# after the conference - see README.md) - applies to every VM Terraform
# directly manages (domain controllers, Cloud Connectors, the GitHub
# runner). Does NOT cover Citrix MCS-provisioned VDAs, which have no static
# Terraform-managed VM resource to attach this to - those are governed by
# each delivery group's own autoscale power_time_schemes instead (see
# terraform.tfvars.example's delivery_groups block). ---

variable "enable_scheduled_shutdown" {
  description = "Whether to attach Azure's native auto-shutdown schedule to every Terraform-managed VM"
  type        = bool
  default     = true
}

variable "scheduled_shutdown_time" {
  description = "Daily auto-shutdown time, 24-hour \"HHmm\" (e.g. \"1900\" for 7:00 PM)"
  type        = string
  default     = "1900"
}

variable "scheduled_shutdown_timezone" {
  description = "Windows time zone ID the auto-shutdown schedule runs in"
  type        = string
  default     = "Eastern Standard Time"
}

variable "enable_boot_diagnostics" {
  description = "Whether to enable Azure boot diagnostics (console screenshot + serial log) on every Terraform-managed VM (domain controllers, Cloud Connectors, the runner) - useful while the environment is still being stood up/validated, safe to turn off afterward. Doesn't cover Citrix MCS-provisioned VDAs - the citrix provider exposes no equivalent setting for those."
  type        = bool
  default     = true
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

variable "citrix_admin_folder_name" {
  description = "Name of the Citrix Studio/Web Studio admin folder this environment's machine catalogs and delivery groups are placed in, alongside other environments/customers' own folders"
  type        = string
  default     = "Driftwood"
}

# --- Golden image versioning / machine catalog rotation ---
# See ../../modules/citrix/README.md for the GitFlow-driven rotation
# convention this drives. No hard entry-count limit per environment - see
# scripts/rotate_image_versions.py's check-outstanding subcommand (warns,
# never blocks).

variable "catalog_rotation" {
  description = "Per-environment golden image build/catalog rotation state, outer-keyed by environment (\"dev\"/\"test\"/\"prod\"), inner-keyed by a build label - either \"<branch-slug>-<short-sha>\" (GitFlow-triggered) or \"YYMM-N\" (manual). CI-managed - sourced from rotation.auto.tfvars.json, not terraform.tfvars."
  type = map(map(object({
    gallery_image_version = string
    total_machines        = number
    machine_count         = number
    machine_naming_scheme = string
    catalog_name          = string
  })))
}

variable "delivery_groups" {
  description = "Static per-environment delivery group config, keyed by environment (\"dev\"/\"test\"/\"prod\") - name, published desktop, access allow-list, autoscale settings, and the catalog-naming conventions the rotation workflow seeds new builds with."
  type = map(object({
    name                                 = string
    published_desktop_name               = string
    desktop_restricted_access_allow_list = list(string)
    autoscale_enabled                    = bool
    autoscale_timezone                   = string
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
    catalog_name_prefix   = string
    machine_naming_scheme = string
  }))
}

variable "citrix_allocation_type" {
  description = "MCS allocation type for the machine catalogs"
  type        = string
  default     = "Random"
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

# --- Active Directory (modules/domain-controllers, modules/cloud-connectors,
# modules/citrix) - replaced the earlier Entra ID-joined/no-AD design after
# real device-join issues in production with no time to chase down before a
# deadline. See modules/domain-controllers/README.md for exactly what gets
# created and the (real, documented) risk of automating AD forest creation
# end-to-end. ---

variable "active_directory_domain_fqdn" {
  description = "FQDN of the new AD DS forest/domain to create (e.g. \"driftwood.local\")"
  type        = string
  default     = "driftwood.local"
}

variable "active_directory_domain_netbios_name" {
  description = "NetBIOS name of the new AD DS forest/domain (e.g. \"DRIFTWOOD\")"
  type        = string
  default     = "DRIFTWOOD"
}

variable "active_directory_safe_mode_password" {
  description = "DSRM (Directory Services Restore Mode) safe mode administrator password for both domain controllers"
  type        = string
  sensitive   = true
}

variable "active_directory_service_account_name" {
  description = "SAM account name of the domain service account created for MCS provisioning and Cloud Connector domain join - added to Domain Admins for simplicity, a deliberate demo-only shortcut (see modules/domain-controllers/README.md), not production practice"
  type        = string
  default     = "svc-mcs"
}

variable "active_directory_service_account_password" {
  description = "Password for the service account named by var.active_directory_service_account_name"
  type        = string
  sensitive   = true
}

variable "active_directory_base_ou_name" {
  description = "Name of the top-level OU created under the domain root"
  type        = string
  default     = "Driftwood"
}

variable "active_directory_vda_ou_name" {
  description = "Name of the VDA computer-account OU created under the base OU"
  type        = string
  default     = "VDAs"
}

variable "active_directory_connector_ou_name" {
  description = "Name of the Cloud Connector computer-account OU created under the base OU"
  type        = string
  default     = "Cloud Connectors"
}

variable "active_directory_dev_desktop_group_name" {
  description = "Name of the AD security group created for the Dev delivery group's desktop access list"
  type        = string
  default     = "Driftwood Dev Desktop Users"
}

variable "active_directory_test_desktop_group_name" {
  description = "Name of the AD security group created for the Test/QA delivery group's desktop access list"
  type        = string
  default     = "Driftwood QA Desktop Users"
}

variable "active_directory_prod_desktop_group_name" {
  description = "Name of the AD security group created for the Prod delivery group's desktop access list"
  type        = string
  default     = "Driftwood Prod Desktop Users"
}

# --- Domain controllers (modules/domain-controllers) ---

variable "domain_controller_admin_username" {
  description = "Local administrator username for the domain controller VMs"
  type        = string
  default     = "dcadmin"
}

variable "domain_controller_admin_password" {
  description = "Local administrator password for the domain controller VMs"
  type        = string
  sensitive   = true
}

variable "domain_controller_scripts_storage_account_name" {
  description = "Globally-unique name for the storage account hosting the domain controllers' own bootstrap scripts (non-secret, publicly-readable by blob URL) - lowercase letters/numbers only, 3-24 characters"
  type        = string
  default     = "driftwooddcscripts"
}

# --- Cloud Connectors (modules/cloud-connectors) ---

variable "cloud_connector_admin_username" {
  description = "Local administrator username for the Cloud Connector VMs"
  type        = string
  default     = "ctxadmin"
}

variable "cloud_connector_admin_password" {
  description = "Local administrator password for the Cloud Connector VMs"
  type        = string
  sensitive   = true
}

variable "cloud_connector_client_id" {
  description = "Citrix Cloud API client ID dedicated to Cloud Connector registration - deliberately separate from citrix_client_id (the Terraform provider's own), so rotating one doesn't couple to the other"
  type        = string
}

variable "cloud_connector_client_secret" {
  description = "Secret for var.cloud_connector_client_id"
  type        = string
  sensitive   = true
}

variable "cloud_connector_installer_url" {
  description = "Read-only SAS URL to the Cloud Connector installer (CWCConnector.exe), operator-uploaded to the artifact-storage blob container - see modules/cloud-connectors/README.md for the upload workflow"
  type        = string
  sensitive   = true
}

variable "cloud_connector_scripts_storage_account_name" {
  description = "Globally-unique name for the storage account hosting the Cloud Connectors' own bootstrap scripts (non-secret, publicly-readable by blob URL) - lowercase letters/numbers only, 3-24 characters"
  type        = string
  default     = "driftwoodccscripts"
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

# Fresh subscriptions have no existing Bastion/VPN/jump host to reach the
# private runner VM - this pair of variables opens a temporary, source-IP-
# scoped path in instead (a public IP on the runner NIC + a matching inbound
# NSG rule), for the one-time SSH registration step in
# bootstrap-github-runner-commands.txt. Leave enable_runner_temporary_ssh_access
# false otherwise; set it true + your current IP, apply, register the
# runner, then set it back to false and re-apply to close the access again.
variable "enable_runner_temporary_ssh_access" {
  description = "Whether to open a temporary public IP + source-IP-scoped NSG rule to SSH into the self-hosted runner VM for one-time registration"
  type        = bool
  default     = false
}

variable "admin_source_ip_cidr" {
  description = "CIDR (e.g. \"203.0.113.5/32\") allowed to SSH into the runner VM while enable_runner_temporary_ssh_access is true - home/mobile IPs are dynamic, re-supply this if it changes"
  type        = string
  default     = null
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
