# Azure AD app registration + service principal that Citrix DaaS uses as the
# hosting connection identity for the Azure hypervisor (citrix_azure_hypervisor).
# This is the "application piece" issued from the Azure side.

resource "azuread_application" "hosting_connection" {
  display_name = var.application_display_name
}

resource "azuread_service_principal" "hosting_connection" {
  client_id = azuread_application.hosting_connection.client_id
}

resource "azuread_application_password" "hosting_connection" {
  application_id = azuread_application.hosting_connection.id
}

resource "azurerm_role_assignment" "hosting_connection" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = var.role_definition_name
  principal_id         = azuread_service_principal.hosting_connection.object_id
}
