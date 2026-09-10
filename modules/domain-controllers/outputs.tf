output "dc_private_ips" {
  description = "Static private IP addresses of the two domain controllers, in creation order [dc-0, dc-1]"
  value       = local.dc_private_ips
}

output "vm_names" {
  description = "Names of the domain controller VMs"
  value       = [for vm in azurerm_windows_virtual_machine.dc : vm.name]
}
