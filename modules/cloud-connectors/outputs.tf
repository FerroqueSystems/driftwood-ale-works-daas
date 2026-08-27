output "vm_names" {
  description = "Names of the Cloud Connector VMs"
  value       = [for vm in azurerm_windows_virtual_machine.connector : vm.name]
}

output "vm_ids" {
  description = "Resource IDs of the Cloud Connector VMs"
  value       = [for vm in azurerm_windows_virtual_machine.connector : vm.id]
}

output "private_ip_addresses" {
  description = "Private IP addresses of the Cloud Connector VMs, in the same order as vm_names"
  value       = [for nic in azurerm_network_interface.connector : nic.private_ip_address]
}
