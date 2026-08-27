variable "resource_group_name" {
  description = "Resource group that owns the network resources"
  type        = string
}

variable "location" {
  description = "Azure region for the network resources"
  type        = string
}

variable "vnet_name" {
  description = "Name of the virtual network for the Citrix resource location"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
}

variable "vda_subnet_name" {
  description = "Name of the subnet hosting Cloud Connectors and VDAs"
  type        = string
  default     = "vda-subnet"
}

variable "vda_subnet_address_prefixes" {
  description = "Address prefixes for the Cloud Connector / VDA subnet"
  type        = list(string)
}

variable "nat_gateway_idle_timeout_minutes" {
  description = "Idle timeout (minutes) for the NAT Gateway providing outbound internet access to the Cloud Connector/VDA subnet"
  type        = number
  default     = 4
}

variable "tags" {
  description = "Tags applied to network resources"
  type        = map(string)
  default     = {}
}
