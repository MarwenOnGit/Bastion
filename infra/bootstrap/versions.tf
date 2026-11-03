terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # Bootstrap state is deliberately local and git-ignored. It holds no secrets
  # (no client secrets are ever created), but it is the record of who can deploy,
  # so keep the file on your laptop and back it up.
}

provider "azurerm" {
  subscription_id     = var.subscription_id
  tenant_id           = var.tenant_id
  storage_use_azuread = true

  # Register every namespace the other stacks and the policy tests use, so the CI
  # identities (which cannot register providers) never need to.
  resource_provider_registrations = "core"
  resource_providers_to_register = [
    "Microsoft.Consumption",
    "Microsoft.CostManagement",
    "Microsoft.ContainerRegistry",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Management",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.PolicyInsights",
    "Microsoft.Security",
    "Microsoft.Storage",
    "Microsoft.Web",
  ]

  features {}
}

provider "azuread" {
  tenant_id = var.tenant_id
}
