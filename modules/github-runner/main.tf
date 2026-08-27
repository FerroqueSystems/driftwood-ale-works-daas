# Self-hosted GitHub Actions runner VM, placed inside the same private subnet
# as the Cloud Connectors so the .github/workflows/cloud-connectors.yml
# workflow can reach them over WinRM to run the Ansible playbook in
# ../../ansible - GitHub-hosted runners have no path into this private VNet.
#
# This module only provisions the bare VM. Registering it with GitHub (runner
# registration tokens are short-lived and deliberately kept out of Terraform
# state/tfvars, consistent with how CITRIX_CLIENT_SECRET is handled in
# providers.tf) is a manual one-time step - see
# ../../environments/citrix-azure/bootstrap-github-runner-commands.txt.

resource "azurerm_network_interface" "runner" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "runner" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.runner.id,
  ]
  tags = var.tags

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_storage_account_type
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}
