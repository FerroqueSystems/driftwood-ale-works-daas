output "client_id" {
  description = "Application (client) ID for the Citrix hosting connection service principal"
  value       = azuread_application.hosting_connection.client_id
}

output "client_secret" {
  description = "Client secret for the Citrix hosting connection service principal"
  value       = azuread_application_password.hosting_connection.value
  sensitive   = true
}

output "service_principal_object_id" {
  description = "Object ID of the hosting connection service principal"
  value       = azuread_service_principal.hosting_connection.object_id
}
