# Identity Module

Creates the Azure AD app registration and service principal that Citrix DaaS
uses as the hosting connection identity for the Azure hypervisor - the
"application piece" issued from the Azure side. The service principal is
granted an RBAC role (default: Contributor) on the target subscription so
Citrix can create, start, and stop machines.

Outputs `client_id` and `client_secret` feed directly into
[modules/citrix](../citrix/README.md)'s `citrix_azure_hypervisor` resource.
