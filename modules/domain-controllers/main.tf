# Two Windows Server domain controllers: dc-0 promotes a brand-new AD DS
# forest, dc-1 joins it as an additional DC for redundancy. Fully scripted
# end-to-end via Custom Script Extensions - see README.md for the (real,
# documented) risk tradeoffs of automating this versus a manual runbook.
#
# Static private IPs (not Dynamic) so every other module that needs to point
# DNS at these domain controllers (modules/network's vnet dns_servers,
# modules/cloud-connectors' NIC-level override) can reference a known value
# at plan time, with no create-order dependency.

locals {
  dc_private_ips = [
    cidrhost(var.subnet_address_prefix, 4),
    cidrhost(var.subnet_address_prefix, 5),
  ]
}

# Hosts this module's own bootstrap scripts (promote-forest.ps1,
# post-promotion-setup.ps1, promote-additional-dc.ps1) - these are generic,
# parameterized automation code with no secrets baked into the file content
# (secrets are passed as Custom Script Extension / Scheduled Task arguments
# instead, see the scripts themselves), so public blob read access is fine
# and avoids the SAS-token expiry/diffing complexity a private container
# would need for a URL these extensions must be able to fetch at VM-create
# time.
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

resource "azurerm_storage_blob" "promote_forest" {
  name                 = "promote-forest.ps1"
  storage_container_id = azurerm_storage_container.scripts.id
  type                 = "Block"
  source               = "${path.module}/scripts/promote-forest.ps1"
  content_md5          = filemd5("${path.module}/scripts/promote-forest.ps1")
}

resource "azurerm_storage_blob" "post_promotion_setup" {
  name                 = "post-promotion-setup.ps1"
  storage_container_id = azurerm_storage_container.scripts.id
  type                 = "Block"
  source               = "${path.module}/scripts/post-promotion-setup.ps1"
  content_md5          = filemd5("${path.module}/scripts/post-promotion-setup.ps1")
}

resource "azurerm_storage_blob" "promote_additional_dc" {
  name                 = "promote-additional-dc.ps1"
  storage_container_id = azurerm_storage_container.scripts.id
  type                 = "Block"
  source               = "${path.module}/scripts/promote-additional-dc.ps1"
  content_md5          = filemd5("${path.module}/scripts/promote-additional-dc.ps1")
}

resource "azurerm_network_interface" "dc" {
  for_each = toset(["0", "1"])

  name                = "${var.name_prefix}-${each.key}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  # Explicit override to Azure's own default resolver - NOT unset/null, which
  # would inherit the VNet-level dns_servers (modules/network points that at
  # these same two DCs). A DC can't resolve anything, including the public
  # blob storage endpoint its own promote-forest.ps1 Custom Script Extension
  # needs to download from, before AD DS/DNS Server has actually been
  # promoted on it - confirmed by a real apply failing with "DNS name
  # resolution failed" fetching that script. Everything else in the VNet
  # (Cloud Connectors, the runner, future VDAs) still resolves through these
  # DCs once they're up, via the VNet-level setting.
  dns_servers = ["168.63.129.16"]

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.dc_private_ips[tonumber(each.key)]
  }
}

resource "azurerm_windows_virtual_machine" "dc" {
  for_each = toset(["0", "1"])

  name                = "${var.name_prefix}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.dc[each.key].id,
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

resource "azurerm_virtual_machine_extension" "promote_forest" {
  name                       = "PromoteADForest"
  virtual_machine_id         = azurerm_windows_virtual_machine.dc["0"].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    fileUris = [
      azurerm_storage_blob.promote_forest.url,
      azurerm_storage_blob.post_promotion_setup.url,
    ]
  })

  # commandToExecute carries the safe mode / service account passwords, so it
  # goes in protected_settings (encrypted at rest, not readable back via the
  # ARM API) rather than plaintext settings.
  #
  # Double-quoted, not single-quoted: Windows Custom Script Extension runs
  # commandToExecute via cmd.exe, which has no concept of single quotes as a
  # quoting mechanism (unlike PowerShell/bash) - a single-quoted value
  # containing a space (e.g. the default "Cloud Connectors" connector OU
  # name, or any of the "Driftwood ... Desktop Users" group names) splits
  # into multiple positional arguments instead of staying one string,
  # confirmed by a real apply failing with "A positional parameter cannot be
  # found that accepts argument 'Connectors'". cmd.exe does honor double
  # quotes for this.
  protected_settings = jsonencode({
    commandToExecute = join(" ", [
      "powershell -NoProfile -ExecutionPolicy Bypass -File promote-forest.ps1",
      "-DomainFqdn \"${var.domain_fqdn}\"",
      "-DomainNetbiosName \"${var.domain_netbios_name}\"",
      "-SafeModePassword \"${var.safe_mode_password}\"",
      "-ServiceAccountName \"${var.service_account_name}\"",
      "-ServiceAccountPassword \"${var.service_account_password}\"",
      "-BaseOuName \"${var.base_ou_name}\"",
      "-VdaOuName \"${var.vda_ou_name}\"",
      "-ConnectorOuName \"${var.connector_ou_name}\"",
      "-DevGroupName \"${var.dev_desktop_group_name}\"",
      "-TestGroupName \"${var.test_desktop_group_name}\"",
      "-ProdGroupName \"${var.prod_desktop_group_name}\"",
    ])
  })
}

# This is a temporary demo environment - auto-shutdown is on by default so
# a forgotten VM doesn't rack up cost after everyone's gone home. Azure's
# native "Auto-shutdown" feature (the same one shown in the Portal), not a
# custom script - it deallocates on its own schedule regardless of what's
# happening inside the guest OS.
resource "azurerm_dev_test_global_vm_shutdown_schedule" "dc" {
  for_each = var.enable_scheduled_shutdown ? azurerm_windows_virtual_machine.dc : {}

  virtual_machine_id    = each.value.id
  location              = var.location
  enabled               = true
  daily_recurrence_time = var.scheduled_shutdown_time
  timezone              = var.scheduled_shutdown_timezone

  notification_settings {
    enabled = false
  }
}

resource "azurerm_virtual_machine_extension" "promote_additional_dc" {
  name                       = "PromoteAdditionalDC"
  virtual_machine_id         = azurerm_windows_virtual_machine.dc["1"].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    fileUris = [
      azurerm_storage_blob.promote_additional_dc.url,
    ]
  })

  protected_settings = jsonencode({
    commandToExecute = join(" ", [
      "powershell -NoProfile -ExecutionPolicy Bypass -File promote-additional-dc.ps1",
      "-DomainFqdn \"${var.domain_fqdn}\"",
      "-DomainNetbiosName \"${var.domain_netbios_name}\"",
      "-Dc1PrivateIp \"${local.dc_private_ips[0]}\"",
      "-SafeModePassword \"${var.safe_mode_password}\"",
      "-ServiceAccountName \"${var.service_account_name}\"",
      "-ServiceAccountPassword \"${var.service_account_password}\"",
    ])
  })

  # Ordering only (resource-creation-call ordering, not functional
  # readiness) - dc-1's script has its own wait-loop for the forest/service
  # account to actually be ready, since DC1's extension reports success
  # before DC1 has even rebooted (see promote-forest.ps1).
  depends_on = [azurerm_virtual_machine_extension.promote_forest]
}
