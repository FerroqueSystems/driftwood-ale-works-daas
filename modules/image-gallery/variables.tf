variable "resource_group_name" {
  description = "Resource group that owns the Shared Image Gallery"
  type        = string
}

variable "location" {
  description = "Azure region for the Shared Image Gallery"
  type        = string
}

variable "gallery_name" {
  description = "Name of the Azure Shared Image Gallery (Azure Compute Gallery) that Packer publishes VDA master images into"
  type        = string
}

variable "image_definition_name" {
  description = "Name of the image definition within the gallery (Packer publishes new versions under this definition)"
  type        = string
}

variable "image_publisher" {
  description = "Publisher value for the image definition identifier"
  type        = string
  default     = "DriftwoodAleWorks"
}

variable "image_offer" {
  description = "Offer value for the image definition identifier"
  type        = string
  default     = "CitrixDaaS"
}

variable "image_sku" {
  description = "SKU value for the image definition identifier"
  type        = string
}

variable "os_type" {
  description = "OS type of the image definition"
  type        = string
  default     = "Windows"
}

variable "hyper_v_generation" {
  description = "Hyper-V generation for the image definition"
  type        = string
  default     = "V2"
}

variable "tags" {
  description = "Tags applied to the gallery and image definition"
  type        = map(string)
  default     = {}
}
