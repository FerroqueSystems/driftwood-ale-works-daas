# Private Azure Storage account + blob container for Packer image build
# artifacts (Citrix VDA installer, Citrix Optimizer zip, custom optimizer
# templates). Packer downloads from this container via short-lived, read-only
# SAS URLs generated out of band - anonymous/public blob access stays disabled.

resource "azurerm_storage_account" "this" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  min_tls_version          = "TLS1_2"

  allow_nested_items_to_be_public = false

  tags = var.tags
}

resource "azurerm_storage_container" "artifacts" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
