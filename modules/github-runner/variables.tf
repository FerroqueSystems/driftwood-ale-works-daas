variable "resource_group_name" {
  description = "Resource group for the self-hosted runner VM"
  type        = string
}

variable "location" {
  description = "Azure region for the self-hosted runner VM"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID the runner VM is placed in (the shared domain controller/Cloud Connector/VDA subnet from modules/network) - runs the citrix-image-rotation.yml workflow's Terraform/Packer steps against resources in this private subnet"
  type        = string
}

variable "private_ip_address" {
  description = "Static private IP for the runner's NIC in that shared subnet - static (not Dynamic) so it can't race the domain controllers' own static .4/.5 reservations for the same address; Terraform creates independent modules' resources in parallel with no implicit ordering, so Dynamic allocation here isn't guaranteed to happen after the DCs claim theirs"
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

variable "enable_scheduled_shutdown" {
  description = "Whether to attach Azure's native auto-shutdown schedule to this VM - this is a demo environment, on by default so it can't be left running (and costing money) by accident"
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
