output "vnet_id" {
  description = "Resource ID of the virtual network"
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.this.name
}

output "vda_subnet_id" {
  description = "Resource ID of the Cloud Connector / VDA subnet"
  value       = azurerm_subnet.vda.id
}

output "vda_subnet_name" {
  description = "Name of the Cloud Connector / VDA subnet"
  value       = azurerm_subnet.vda.name
}

output "nat_gateway_public_ip" {
  description = "Public IP address used for outbound internet access from the Cloud Connector / VDA subnet"
  value       = azurerm_public_ip.nat.ip_address
}
