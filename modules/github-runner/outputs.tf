output "vm_name" {
  description = "Name of the runner VM"
  value       = azurerm_linux_virtual_machine.runner.name
}

output "private_ip_address" {
  description = "Private IP address of the runner VM"
  value       = azurerm_network_interface.runner.private_ip_address
}

output "temporary_public_ip_address" {
  description = "Temporary public IP address of the runner VM, if var.enable_temporary_public_access is true - null otherwise"
  value       = try(azurerm_public_ip.runner_temp[0].ip_address, null)
}
