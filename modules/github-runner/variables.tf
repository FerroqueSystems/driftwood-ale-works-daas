variable "resource_group_name" {
  description = "Resource group for the self-hosted runner VM"
  type        = string
}

variable "location" {
  description = "Azure region for the self-hosted runner VM"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID the runner VM is placed in (the shared Cloud Connector/VDA subnet from modules/network) - it needs network line-of-sight to the Cloud Connector VMs to run Ansible over WinRM"
  type        = string
}

variable "name" {
  description = "Name of the runner VM"
  type        = string
  default     = "driftwood-gh-runner"
}

variable "vm_size" {
  description = "Azure VM size for the runner VM"
  type        = string
  default     = "Standard_B2s"
}

variable "os_disk_storage_account_type" {
  description = "Storage account type for the runner VM's OS disk"
  type        = string
  default     = "StandardSSD_LRS"
}

variable "admin_username" {
  description = "Admin username for the runner VM"
  type        = string
  default     = "ghrunner"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the admin user - the runner VM uses key-based auth only (no password)"
  type        = string
}

variable "tags" {
  description = "Tags applied to the runner VM"
  type        = map(string)
  default     = {}
}

variable "enable_temporary_public_access" {
  description = "Whether to attach a temporary public IP to the runner VM's NIC, for one-time SSH registration in a subscription with no other connectivity path (Bastion/VPN/jump host) - see bootstrap-github-runner-commands.txt. Requires a matching NSG allow rule (modules/network's admin_ssh_source_cidr)."
  type        = bool
  default     = false
}
