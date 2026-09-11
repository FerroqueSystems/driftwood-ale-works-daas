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
  description = "Azure VM size for the Cloud Connector VMs - Citrix's installer requires at least 4 vCPUs/6GB RAM/20GB disk"
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
  description = "Local administrator password for the Cloud Connector VMs"
  type        = string
  sensitive   = true
}

variable "dns_servers" {
  description = "DNS servers (the two domain controllers' static private IPs, from module.domain_controllers) each connector's NIC uses to resolve the AD domain - index 0/1 are also used directly as the domain controllers to query in the wait-for-domain readiness check"
  type        = list(string)
}

variable "domain_fqdn" {
  description = "FQDN of the AD domain to join (e.g. \"driftwood.local\")"
  type        = string
}

variable "domain_netbios_name" {
  description = "NetBIOS name of the AD domain to join (e.g. \"DRIFTWOOD\")"
  type        = string
}

variable "connector_ou_dn" {
  description = "Distinguished name of the OU Cloud Connector computer accounts are created into (e.g. \"OU=Cloud Connectors,OU=Driftwood,DC=driftwood,DC=local\")"
  type        = string
}

variable "service_account_name" {
  description = "SAM account name of the domain service account used to join these VMs to the domain (created by modules/domain-controllers)"
  type        = string
}

variable "service_account_password" {
  description = "Password for var.service_account_name"
  type        = string
  sensitive   = true
}

variable "citrix_customer_id" {
  description = "Citrix Cloud customer ID (used as the Cloud Connector installer's customerName parameter)"
  type        = string
}

variable "cloud_connector_client_id" {
  description = "Citrix Cloud API client ID dedicated to Cloud Connector registration - deliberately separate from the Terraform provider's own citrix_client_id, so rotating one doesn't couple to the other"
  type        = string
}

variable "cloud_connector_client_secret" {
  description = "Secret for var.cloud_connector_client_id"
  type        = string
  sensitive   = true
}

variable "citrix_resource_location_id" {
  description = "ID of the Citrix Cloud resource location Cloud Connectors register into (module.citrix's resource_location_id output)"
  type        = string
}

variable "cloud_connector_installer_url" {
  description = "Read-only SAS URL to the Cloud Connector installer (CWCConnector.exe), operator-uploaded to the artifact-storage blob container - it's a Citrix-licensed binary tied to your Citrix Cloud account, downloaded from the Citrix Cloud console, so it can't be fetched automatically. See this module's README for the upload workflow."
  type        = string
  sensitive   = true
}

variable "scripts_storage_account_name" {
  description = "Globally-unique name for the storage account hosting this module's own bootstrap scripts (non-secret, generic automation code), publicly-readable by blob URL - lowercase letters/numbers only, 3-24 characters"
  type        = string
}

variable "tags" {
  description = "Tags applied to the Cloud Connector VMs"
  type        = map(string)
  default     = {}
}

variable "enable_scheduled_shutdown" {
  description = "Whether to attach Azure's native auto-shutdown schedule to these VMs - this is a demo environment, on by default so it can't be left running (and costing money) by accident"
  type        = bool
  default     = true
}

variable "enable_boot_diagnostics" {
  description = "Whether to enable Azure boot diagnostics (console screenshot + serial log) on these VMs - useful while the environment is still being stood up/validated, safe to turn off afterward"
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
