# Citrix Cloud Connector VMs for the Azure resource location. Cloud
# Connectors broker communication between Citrix Cloud and this Azure
# subscription/on-prem AD domain (the hypervisor connection, domain-joined
# VDA registration and brokering) - see
# https://community.citrix.com/tech-zone/automation/automation-handbook-2601-part5/
#
# Domain-joined (traditional AD, not Entra ID) via the standard Azure
# JsonADDomainExtension, then the Cloud Connector software itself is
# installed/registered by a Custom Script Extension - see
# scripts/install-cloud-connector.ps1. Both wait behind
# scripts/wait-for-domain.ps1, since modules/domain-controllers' own
# extensions report success before their post-promotion reboots even
# complete - a real race without an explicit wait here.

locals {
  connector_indices = toset([for i in range(var.connector_count) : tostring(i)])
}

# Hosts this module's own bootstrap scripts (wait-for-domain.ps1,
# install-cloud-connector.ps1) - generic, parameterized automation code with
# no secrets baked into the file content (secrets are passed as extension
# arguments instead), so public blob read access is fine here. The actual
# Cloud Connector installer (a Citrix-licensed binary, see
# var.cloud_connector_installer_url) is NOT hosted here - that one is
# operator-uploaded to the private artifact-storage container instead, see
# this module's README.
resource "azurerm_storage_account" "scripts" {
  name                            = var.scripts_storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = true
  tags                            = var.tags
}

resource "azurerm_storage_container" "scripts" {
  name                  = "bootstrap-scripts"
  storage_account_id    = azurerm_storage_account.scripts.id
  container_access_type = "blob"
}

resource "azurerm_storage_blob" "wait_for_domain" {
  name                 = "wait-for-domain.ps1"
  storage_container_id = azurerm_storage_container.scripts.id
  type                 = "Block"
  source               = "${path.module}/scripts/wait-for-domain.ps1"
  content_md5          = filemd5("${path.module}/scripts/wait-for-domain.ps1")
}

resource "azurerm_storage_blob" "install_cloud_connector" {
  name                 = "install-cloud-connector.ps1"
  storage_container_id = azurerm_storage_container.scripts.id
  type                 = "Block"
  source               = "${path.module}/scripts/install-cloud-connector.ps1"
  content_md5          = filemd5("${path.module}/scripts/install-cloud-connector.ps1")
}

resource "azurerm_network_interface" "connector" {
  for_each = local.connector_indices

  name                = "${var.name_prefix}-${each.key}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  dns_servers         = var.dns_servers

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "connector" {
  for_each = local.connector_indices

  name = "${var.name_prefix}-${each.key}"
  # Windows computer_name (the actual guest OS/NetBIOS hostname) is capped at
  # 15 characters, unlike the Azure resource name above - defaulting to the
  # Azure name here fails outright once name_prefix pushes past that limit
  # (confirmed by a real apply: the default "driftwood-cloud-connector-0/1"
  # is 27 characters). Short and explicit avoids depending on name_prefix
  # staying under any particular length.
  computer_name       = "dw-cc-${each.key}"
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

  # On while the environment is still being stood up/validated (console
  # screenshots + serial log, useful for diagnosing a VM that boots but
  # never becomes reachable) - Azure-managed storage (storage_account_uri
  # left unset) rather than a dedicated storage account. Toggle off once
  # the environment's proven.
  dynamic "boot_diagnostics" {
    for_each = var.enable_boot_diagnostics ? [1] : []
    content {}
  }
}

# This is a temporary demo environment - auto-shutdown is on by default so
# a forgotten VM doesn't rack up cost after everyone's gone home. Azure's
# native "Auto-shutdown" feature, not a custom script.
resource "azurerm_dev_test_global_vm_shutdown_schedule" "connector" {
  for_each = var.enable_scheduled_shutdown ? azurerm_windows_virtual_machine.connector : {}

  virtual_machine_id    = each.value.id
  location              = var.location
  enabled               = true
  daily_recurrence_time = var.scheduled_shutdown_time
  timezone              = var.scheduled_shutdown_timezone

  notification_settings {
    enabled = false
  }
}


# Azure only allows one CustomScriptExtension handler per Windows VM
# (confirmed by a real apply: adding this as a second azurerm_virtual_
# machine_extension alongside install_connector below failed with
# "Multiple VMExtensions per handler not supported for OS type 'Windows'").
# azurerm_virtual_machine_run_command is a separate mechanism entirely (the
# newer Azure "Run Command" feature, not a VM Extension handler), so it
# doesn't conflict - same script blob, just invoked a different way, with
# named parameter blocks instead of a raw commandToExecute string.
#
# Named distinctly from the old "WaitForDomain" VM Extension this replaced
# (not reused) - Run Commands and Extensions apparently share one name
# namespace per VM, and a real apply hit a 409 Conflict ("already used by
# another VM extension resource") creating this under the old name even
# moments after that extension's own deletion had already reported
# "Destruction complete" - Azure-side propagation lag, not something a
# retry alone reliably clears. A distinct name sidesteps it outright.
resource "azurerm_virtual_machine_run_command" "wait_for_domain" {
  for_each = azurerm_windows_virtual_machine.connector

  name               = "WaitForDomainRunCommand"
  location           = var.location
  virtual_machine_id = each.value.id

  source {
    script_uri = azurerm_storage_blob.wait_for_domain.url
  }

  parameter {
    name  = "DomainFqdn"
    value = var.domain_fqdn
  }
  parameter {
    name  = "Dc1PrivateIp"
    value = var.dns_servers[0]
  }
  parameter {
    name  = "Dc2PrivateIp"
    value = var.dns_servers[1]
  }
}

resource "azurerm_virtual_machine_extension" "domain_join" {
  for_each = azurerm_windows_virtual_machine.connector

  name                       = "DomainJoin"
  virtual_machine_id         = each.value.id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    Name    = var.domain_fqdn
    OUPath  = var.connector_ou_dn
    User    = "${var.domain_netbios_name}\\${var.service_account_name}"
    Restart = true
    Options = 3
  })

  # Password carries the domain service account's credential, so it goes in
  # protected_settings (encrypted at rest, not readable back via the ARM
  # API) rather than plaintext settings.
  protected_settings = jsonencode({
    Password = var.service_account_password
  })

  depends_on = [azurerm_virtual_machine_run_command.wait_for_domain]
}

resource "azurerm_virtual_machine_extension" "install_connector" {
  for_each = azurerm_windows_virtual_machine.connector

  name                       = "InstallCloudConnector"
  virtual_machine_id         = each.value.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    fileUris = [azurerm_storage_blob.install_cloud_connector.url]
  })

  # commandToExecute carries the Cloud Connector installer's SAS URL and the
  # Citrix Cloud API client secret, so it goes in protected_settings.
  protected_settings = jsonencode({
    commandToExecute = join(" ", [
      "powershell -NoProfile -ExecutionPolicy Bypass -File install-cloud-connector.ps1",
      "-InstallerUrl \"${var.cloud_connector_installer_url}\"",
      "-CustomerName \"${var.citrix_customer_id}\"",
      "-ClientId \"${var.cloud_connector_client_id}\"",
      "-ClientSecret \"${var.cloud_connector_client_secret}\"",
      "-ResourceLocationId \"${var.citrix_resource_location_id}\"",
    ])
  })

  depends_on = [azurerm_virtual_machine_extension.domain_join]
}
