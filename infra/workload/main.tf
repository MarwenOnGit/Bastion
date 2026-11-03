# ---------------------------------------------------------------------------
# Sample workload in the spoke: one storage account and one Key Vault.
#   - public network access disabled on both
#   - reachable only through private endpoints (2 in total, the cost cap)
#   - storage: shared key access disabled, Entra ID only
#   - Key Vault: RBAC authorisation, no access policies
#
# This stack costs about $16 a month while it exists (see docs/COST.md). It is
# designed to be applied for a demo and destroyed afterwards.
# ---------------------------------------------------------------------------

data "azurerm_resource_group" "spoke" {
  name = var.spoke_resource_group
}

data "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  virtual_network_name = "vnet-bastion-spoke-app"
  resource_group_name  = var.spoke_resource_group
}

data "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.hub_resource_group
}

data "azurerm_private_dns_zone" "vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.hub_resource_group
}

locals {
  suffix = substr(sha1(var.subscription_id), 0, 6)

  tags = {
    owner   = var.owner_tag
    env     = "lab"
    project = "bastion"
  }
}

resource "azurerm_storage_account" "app" {
  #checkov:skip=CKV_AZURE_206:LRS is enough for a lab sample; geo-replication doubles the cost.
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed keys keep the sample free; a customer-managed key needs a key in Key Vault and a third private path.
  #checkov:skip=CKV_AZURE_33:Queue service is not used, and queue logging would need data-plane access from the runner.
  name                              = "stbastionapp${local.suffix}"
  resource_group_name               = data.azurerm_resource_group.spoke.name
  location                          = var.location
  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = false
  local_user_enabled                = false
  sftp_enabled                      = false
  infrastructure_encryption_enabled = true
  cross_tenant_replication_enabled  = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

resource "azurerm_key_vault" "app" {
  name                          = "kv-bastion-${local.suffix}"
  resource_group_name           = data.azurerm_resource_group.spoke.name
  location                      = var.location
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  enable_rbac_authorization     = true
  public_network_access_enabled = false
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  tags = local.tags
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${azurerm_storage_account.app.name}-blob"
  resource_group_name = data.azurerm_resource_group.spoke.name
  location            = var.location
  subnet_id           = data.azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azurerm_storage_account.app.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.blob.id]
  }

  tags = local.tags
}

resource "azurerm_private_endpoint" "vault" {
  name                = "pe-${azurerm_key_vault.app.name}-vault"
  resource_group_name = data.azurerm_resource_group.spoke.name
  location            = var.location
  subnet_id           = data.azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-vault"
    private_connection_resource_id = azurerm_key_vault.app.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.vault.id]
  }

  tags = local.tags
}
