# Self-hosted GitHub Actions runner VM, placed inside the private VDA subnet
# so .github/workflows/citrix-image-rotation.yml's Terraform/Packer steps can
# reach resources in it - GitHub-hosted runners have no path into this
# private VNet.
#
# This module only provisions the bare VM. Registering it with GitHub (runner
# registration tokens are short-lived and deliberately kept out of Terraform
# state/tfvars, consistent with how CITRIX_CLIENT_SECRET is handled in
# providers.tf) is a manual one-time step - see
# ../../environments/citrix-azure/bootstrap-github-runner-commands.txt.

# Temporary, source-IP-scoped public IP for the one-time SSH registration
# step in a subscription with no other connectivity path (Bastion/VPN/jump
# host) - see var.enable_temporary_public_access. Requires a matching NSG
# allow rule (modules/network's admin_ssh_source_cidr) to actually admit
# traffic; this alone isn't sufficient since Azure evaluates subnet-level and
# NIC-level NSGs independently.
resource "azurerm_public_ip" "runner_temp" {
  count               = var.enable_temporary_public_access ? 1 : 0
  name                = "${var.name}-temp-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "runner" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_temporary_public_access ? one(azurerm_public_ip.runner_temp[*].id) : null
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

# This is a temporary demo environment - auto-shutdown is on by default so
# a forgotten VM doesn't rack up cost after everyone's gone home. Azure's
# native "Auto-shutdown" feature, not a custom script. Note: citrix-image-
# rotation.yml needs this runner powered on to do anything - if it's been
# auto-shutdown, start it first (see scripts/manage-demo-vms.ps1) before
# triggering that workflow.
resource "azurerm_dev_test_global_vm_shutdown_schedule" "runner" {
  count = var.enable_scheduled_shutdown ? 1 : 0

  virtual_machine_id    = azurerm_linux_virtual_machine.runner.id
  location              = var.location
  enabled               = true
  daily_recurrence_time = var.scheduled_shutdown_time
  timezone              = var.scheduled_shutdown_timezone

  notification_settings {
    enabled = false
  }
}
