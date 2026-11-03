terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # storage_account_name is passed with -backend-config (repository variable
  # TFSTATE_STORAGE_ACCOUNT). Auth is Entra ID only: the account has shared keys disabled.
  backend "azurerm" {
    resource_group_name = "bastion-tfstate-rg"
    container_name      = "tfstate"
    key                 = "network.tfstate"
    use_azuread_auth    = true
  }
}

provider "azurerm" {
  subscription_id     = var.subscription_id
  tenant_id           = var.tenant_id
  storage_use_azuread = true

  features {}
}
