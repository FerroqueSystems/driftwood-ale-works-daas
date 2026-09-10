variable "resource_group_name" {
  description = "Resource group for the domain controller VMs"
  type        = string
}

variable "location" {
  description = "Azure region for the domain controller VMs"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID the domain controllers are placed in"
  type        = string
}

variable "subnet_address_prefix" {
  description = "CIDR of the subnet in var.subnet_id - used to compute static IPs for the two domain controllers (cidrhost offsets 4 and 5, the first two usable addresses in any Azure subnet)"
  type        = string
}

variable "name_prefix" {
  description = "Name prefix for the domain controller VMs - each is named \"<prefix>-<index>\""
  type        = string
  default     = "driftwood-dc"
}

variable "vm_size" {
  description = "Azure VM size for the domain controller VMs"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "os_disk_storage_account_type" {
  description = "Storage account type for the domain controller VMs' OS disks"
  type        = string
  default     = "StandardSSD_LRS"
}

variable "admin_username" {
  description = "Local administrator username for the domain controller VMs"
  type        = string
  default     = "dcadmin"
}

variable "admin_password" {
  description = "Local administrator password for the domain controller VMs"
  type        = string
  sensitive   = true
}

variable "domain_fqdn" {
  description = "FQDN of the new AD DS forest/domain to create (e.g. \"driftwood.local\")"
  type        = string
}

variable "domain_netbios_name" {
  description = "NetBIOS name of the new AD DS forest/domain (e.g. \"DRIFTWOOD\")"
  type        = string
}

variable "safe_mode_password" {
  description = "DSRM (Directory Services Restore Mode) safe mode administrator password for both domain controllers"
  type        = string
  sensitive   = true
}

variable "service_account_name" {
  description = "SAM account name of the domain service account created for MCS provisioning and Cloud Connector domain join (e.g. \"svc-mcs\") - added to Domain Admins for simplicity, a deliberate demo-only shortcut (see README), not production practice"
  type        = string
  default     = "svc-mcs"
}

variable "service_account_password" {
  description = "Password for the service account named by var.service_account_name"
  type        = string
  sensitive   = true
}

variable "base_ou_name" {
  description = "Name of the top-level OU created under the domain root"
  type        = string
  default     = "Driftwood"
}

variable "vda_ou_name" {
  description = "Name of the VDA computer-account OU created under the base OU"
  type        = string
  default     = "VDAs"
}

variable "connector_ou_name" {
  description = "Name of the Cloud Connector computer-account OU created under the base OU"
  type        = string
  default     = "Cloud Connectors"
}

variable "dev_desktop_group_name" {
  description = "Name of the AD security group created for the Dev delivery group's desktop access list"
  type        = string
  default     = "Driftwood Dev Desktop Users"
}

variable "test_desktop_group_name" {
  description = "Name of the AD security group created for the Test/QA delivery group's desktop access list"
  type        = string
  default     = "Driftwood QA Desktop Users"
}

variable "prod_desktop_group_name" {
  description = "Name of the AD security group created for the Prod delivery group's desktop access list"
  type        = string
  default     = "Driftwood Prod Desktop Users"
}

variable "scripts_storage_account_name" {
  description = "Globally-unique name for the storage account hosting this module's own bootstrap scripts (non-secret, generic automation code - secrets are passed as extension/scheduled-task arguments, never baked into script content), publicly-readable by blob URL - lowercase letters/numbers only, 3-24 characters"
  type        = string
}

variable "tags" {
  description = "Tags applied to resources this module creates"
  type        = map(string)
  default     = {}
}

variable "enable_scheduled_shutdown" {
  description = "Whether to attach Azure's native auto-shutdown schedule to these VMs - this is a demo environment, on by default so it can't be left running (and costing money) by accident"
  type        = bool
  default     = true
}

variable "scheduled_shutdown_time" {
  description = "Daily auto-shutdown time, 24-hour \"HHmm\" (e.g. \"1900\" for 7:00 PM)"
  type        = string
  default     = "1900"
}

variable "scheduled_shutdown_timezone" {
  description = "Windows time zone ID (e.g. \"Eastern Standard Time\") the auto-shutdown schedule runs in"
  type        = string
  default     = "Eastern Standard Time"
}
