data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

locals {
  # Deterministic, non-secret suffix so every stack can derive globally unique names
  # without reading another stack's state.
  suffix = substr(sha1(var.subscription_id), 0, 6)

  tags = {
    owner   = var.owner_tag
    env     = "lab"
    project = "bastion"
  }

  subscription_scope = "/subscriptions/${var.subscription_id}"

  # Bastion's own resource groups. The only places Bastion creates resources and the
  # only scopes where the bastion-baseline initiative is assigned with real effects.
  resource_groups = {
    tfstate   = "bastion-tfstate-rg"
    hub       = "bastion-hub-rg"
    spoke_app = "bastion-spoke-app-rg"
    test      = "bastion-test-rg"
  }

  tfstate_account_name   = "stbastiontf${local.suffix}"
  tfstate_container_name = "tfstate"
}

resource "azurerm_resource_group" "this" {
  for_each = local.resource_groups

  name     = each.value
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Terraform state for the governance, network and workload stacks.
# Entra ID auth only: no shared keys, no SAS, no anonymous blob access.
# Public network access stays on because GitHub-hosted runners have no private
# path into the VNet; access is controlled by Entra ID and RBAC instead.
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "tfstate" {
  #checkov:skip=CKV_AZURE_59:GitHub-hosted runners need a public endpoint. Shared keys are disabled, so only Entra ID tokens with a data role on the container work.
  #checkov:skip=CKV2_AZURE_33:A private endpoint for state would be a third private endpoint (cost cap is 2) and runners could not reach it.
  #checkov:skip=CKV_AZURE_33:Queue service is not used.
  #checkov:skip=CKV_AZURE_206:LRS is enough for a lab; blob versioning and soft delete protect against bad writes.
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed keys are used to stay free; a customer-managed key needs Key Vault on the bootstrap path.
  name                              = local.tfstate_account_name
  resource_group_name               = azurerm_resource_group.this["tfstate"].name
  location                          = var.location
  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = true
  local_user_enabled                = false
  sftp_enabled                      = false
  infrastructure_encryption_enabled = true
  cross_tenant_replication_enabled  = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  #checkov:skip=CKV2_AZURE_21:Blob logs are sent to law-huginn by azurerm_monitor_diagnostic_setting.tfstate_blob; checkov only recognises the legacy storage logging block.
  name                  = local.tfstate_container_name
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

locals {
  tfstate_container_scope = "${azurerm_storage_account.tfstate.id}/blobServices/default/containers/${local.tfstate_container_name}"
}

# The person running the bootstrap also gets data access to the state container, so they
# can inspect or repair state with `az storage blob ... --auth-mode login`.
resource "azurerm_role_assignment" "operator_state" {
  scope                = local.tfstate_container_scope
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  description          = "Bastion bootstrap operator: state access"
}

# Who read or wrote Terraform state ends up in Huggin's workspace (StorageBlobLogs).
resource "azurerm_monitor_diagnostic_setting" "tfstate_blob" {
  name                       = "bastion-to-law-huginn"
  target_resource_id         = "${azurerm_storage_account.tfstate.id}/blobServices/default"
  log_analytics_workspace_id = local.huginn_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}
