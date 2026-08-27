terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    citrix = {
      source  = "citrix/citrix"
      version = ">= 1.0"
    }
  }
}

provider "azurerm" {
  features {}
  # Authenticate via `az login`, ARM_* environment variables, or OIDC in CI -
  # do not hardcode a service principal secret here.
}

provider "azuread" {
  # Uses the same authentication context as azurerm above.
}

provider "citrix" {
  cvad_config = {
    customer_id = var.citrix_customer_id
    client_id   = var.citrix_client_id
    environment = var.citrix_environment
    # client_secret is intentionally omitted here - set it via the
    # CITRIX_CLIENT_SECRET environment variable instead of tfvars/state.
  }
}
