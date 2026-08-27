variable "application_display_name" {
  description = "Display name for the Azure AD app registration used as the Citrix hosting connection service principal"
  type        = string
  default     = "driftwood-citrix-daas-hosting-connection"
}

variable "subscription_id" {
  description = "Azure subscription ID the hosting connection service principal is granted access to"
  type        = string
}

variable "role_definition_name" {
  description = "Azure RBAC role granted to the hosting connection service principal"
  type        = string
  default     = "Contributor"
}
