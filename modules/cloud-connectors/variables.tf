variable "resource_group_name" {
  description = "Resource group for the Cloud Connector VMs"
  type        = string
}

variable "location" {
  description = "Azure region for the Cloud Connector VMs"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID the Cloud Connector VMs are placed in (the shared Cloud Connector/VDA subnet from modules/network)"
  type        = string
}

variable "connector_count" {
  description = "Number of Cloud Connector VMs - Citrix recommends at least 2 per resource location for high availability"
  type        = number
  default     = 2
}

variable "name_prefix" {
  description = "Name prefix for Cloud Connector VMs - each is named \"<prefix>-<index>\""
  type        = string
  default     = "driftwood-cloud-connector"
}

variable "vm_size" {
  description = "Azure VM size for the Cloud Connector VMs - Citrix's installer requires at least 4 vCPUs/6GB RAM/20GB disk, see ansible/roles/citrix_cloud_connector"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "os_disk_storage_account_type" {
  description = "Storage account type for the Cloud Connector VMs' OS disks"
  type        = string
  default     = "StandardSSD_LRS"
}

variable "admin_username" {
  description = "Local administrator username for the Cloud Connector VMs"
  type        = string
  default     = "ctxadmin"
}

variable "admin_password" {
  description = "Local administrator password for the Cloud Connector VMs - supply via the TF_VAR_cloud_connector_admin_password environment variable, never in a committed tfvars file"
  type        = string
  sensitive   = true
}

variable "winrm_bootstrap_script_url" {
  description = "Read-only SAS URL to the vendored ConfigureRemotingForAnsible.ps1 script (../../ansible/files/ConfigureRemotingForAnsible.ps1) staged in the artifact-storage blob container - see modules/artifact-storage and this module's README for the upload workflow"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags applied to the Cloud Connector VMs"
  type        = map(string)
  default     = {}
}
