variable "resource_group_name" {
  description = "Resource group that owns the artifact storage account"
  type        = string
}

variable "location" {
  description = "Azure region for the artifact storage account"
  type        = string
}

variable "storage_account_name" {
  description = "Globally-unique name for the artifact storage account (lowercase letters/numbers only, 3-24 characters)"
  type        = string
}

variable "container_name" {
  description = "Name of the private blob container that holds image build artifacts"
  type        = string
  default     = "image-build-artifacts"
}

variable "account_tier" {
  description = "Performance tier of the storage account"
  type        = string
  default     = "Standard"
}

variable "account_replication_type" {
  description = "Replication type of the storage account"
  type        = string
  default     = "LRS"
}

variable "tags" {
  description = "Tags applied to the storage account"
  type        = map(string)
  default     = {}
}
