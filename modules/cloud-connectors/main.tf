# Citrix Cloud Connector VMs for the Azure resource location. Cloud Connectors
# broker communication between Citrix Cloud and this Azure subscription (the
# hypervisor connection, AD/Entra ID, and VDA registration) - see
# https://community.citrix.com/tech-zone/automation/automation-handbook-2601-part5/
#
# These VMs are provisioned here; the Cloud Connector software itself is
# installed/registered by the Ansible playbook in ../../ansible (run from the
# self-hosted GitHub Actions runner in ../github-runner, since it needs
# network line-of-sight to this private subnet).

resource "azurerm_network_interface" "connector" {
  for_each = toset([for i in range(var.connector_count) : tostring(i)])

  name                = "${var.name_prefix}-${each.key}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "connector" {
  for_each = toset([for i in range(var.connector_count) : tostring(i)])

  name                = "${var.name_prefix}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.connector[each.key].id,
  ]
  tags = var.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_storage_account_type
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
}

# Entra ID join, consistent with the AzureAD identity_type used for the VDA
# machine catalog (see modules/citrix) - no traditional AD domain in this
# design.
resource "azurerm_virtual_machine_extension" "aad_login" {
  for_each = azurerm_windows_virtual_machine.connector

  name                       = "AADLoginForWindows"
  virtual_machine_id         = each.value.id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true
}

# Enables a WinRM HTTPS listener (self-signed cert) using Ansible's own
# well-known bootstrap script, so ../../ansible can reach these VMs from the
# self-hosted runner in ../github-runner. Internal-network-only, no NSG
# inbound rule opens this up externally (see modules/network).
#
# fileUris points at a SAS URL to the vendored copy of the script
# (../../ansible/files/ConfigureRemotingForAnsible.ps1) staged in the
# artifact-storage blob container, not a live fetch from GitHub - that avoids
# a hard runtime dependency on an outside, unpinned third-party URL and on
# this subnet having outbound internet access at all (see modules/network's
# NAT Gateway).
resource "azurerm_virtual_machine_extension" "winrm" {
  for_each = azurerm_windows_virtual_machine.connector

  name                       = "ConfigureRemotingForAnsible"
  virtual_machine_id         = each.value.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  # fileUris carries a SAS token, so it goes in protected_settings (encrypted
  # at rest, not readable back via the ARM API) rather than plaintext
  # settings - see https://learn.microsoft.com/azure/virtual-machines/extensions/custom-script-windows#properties.
  protected_settings = jsonencode({
    fileUris = [
      var.winrm_bootstrap_script_url
    ]
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -File ConfigureRemotingForAnsible.ps1 -ForceNewSSLCert"
  })

  depends_on = [azurerm_virtual_machine_extension.aad_login]
}
