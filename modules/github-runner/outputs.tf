output "vm_name" {
  description = "Name of the runner VM"
  value       = azurerm_linux_virtual_machine.runner.name
}

output "private_ip_address" {
  description = "Private IP address of the runner VM"
  value       = azurerm_network_interface.runner.private_ip_address
}
