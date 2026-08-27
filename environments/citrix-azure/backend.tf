terraform {
  backend "azurerm" {
    resource_group_name  = "rg-driftwood-tfstate"
    storage_account_name = "driftwoodtfstate"
    container_name       = "tfstate"
    key                  = "citrix-azure.tfstate"
  }
}
