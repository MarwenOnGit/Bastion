# ---------------------------------------------------------------------------
# Role assignments for the CI identities. Least privilege, explained in
# docs/adr/0006-ci-identities-and-least-privilege.md.
#
# No CI identity gets Owner, User Access Administrator, Role Based Access
# Control Administrator or any Microsoft Graph permission. Everything that needs
# those rights (app registrations, custom roles, role assignments, management
# groups) lives in this bootstrap, which only a human runs.
# ---------------------------------------------------------------------------

locals {
  rg_ids = { for k, rg in azurerm_resource_group.this : k => rg.id }

  ci_role_assignments = {
    # Plan and drift: read everything, read state. Plans run with -lock=false so no
    # blob lease (write) is needed.
    "plan/reader-sub"         = { identity = "plan", role = "Reader", scope = local.subscription_scope }
    "plan/state-reader"       = { identity = "plan", role = "Storage Blob Data Reader", scope = local.tfstate_container_scope }
    "apply/reader-sub"        = { identity = "apply", role = "Reader", scope = local.subscription_scope }
    "apply/policy-sub"        = { identity = "apply", role = "Resource Policy Contributor", scope = local.subscription_scope }
    "apply/cost-sub"          = { identity = "apply", role = "Cost Management Contributor", scope = local.subscription_scope }
    "apply/security-sub"      = { identity = "apply", role = "Security Admin", scope = local.subscription_scope }
    "apply/contributor-hub"   = { identity = "apply", role = "Contributor", scope = local.rg_ids["hub"] }
    "apply/contributor-spoke" = { identity = "apply", role = "Contributor", scope = local.rg_ids["spoke_app"] }
    "apply/state-writer"      = { identity = "apply", role = "Storage Blob Data Contributor", scope = local.tfstate_container_scope }
    "tester/contributor-test" = { identity = "policy_tester", role = "Contributor", scope = local.rg_ids["test"] }
  }
}

resource "azurerm_role_assignment" "ci" {
  for_each = local.ci_role_assignments

  scope                            = each.value.scope
  role_definition_name             = each.value.role
  principal_id                     = azuread_service_principal.ci[each.value.identity].object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Bastion ${each.key}"
}

# ---------------------------------------------------------------------------
# Custom role: operate VMs without being able to run code on them.
# Azure Policy cannot block actions such as Run Command (Fenrir X-08) or
# container exec (X-14). Only RBAC can. See docs/adr/0008.
#
# NotActions is not a deny: it only removes actions from this one role. If the
# same principal also holds Contributor, Run Command is still allowed. That is
# why no human or workload holds a standing Contributor or Owner on the workload
# resource groups.
# ---------------------------------------------------------------------------
resource "azurerm_role_definition" "vm_operator" {
  name        = "Bastion VM Operator"
  scope       = local.subscription_scope
  description = "Start, stop, restart and read VMs and container groups in Bastion workload groups. Cannot run commands, exec into containers, install extensions or read publishing credentials."

  permissions {
    actions = [
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/instanceView/read",
      "Microsoft.Compute/virtualMachines/start/action",
      "Microsoft.Compute/virtualMachines/restart/action",
      "Microsoft.Compute/virtualMachines/powerOff/action",
      "Microsoft.Compute/virtualMachines/deallocate/action",
      "Microsoft.Compute/disks/read",
      "Microsoft.Network/networkInterfaces/read",
      "Microsoft.ContainerInstance/containerGroups/read",
      "Microsoft.ContainerInstance/containerGroups/start/action",
      "Microsoft.ContainerInstance/containerGroups/stop/action",
      "Microsoft.ContainerInstance/containerGroups/restart/action",
      "Microsoft.Insights/metrics/read",
    ]

    # Listed for clarity and as a guard if someone later widens `actions` with a wildcard.
    not_actions = [
      "Microsoft.Compute/virtualMachines/runCommand/action",
      "Microsoft.Compute/virtualMachines/runCommands/write",
      "Microsoft.Compute/virtualMachines/extensions/write",
      "Microsoft.Compute/virtualMachines/login/action",
      "Microsoft.Compute/virtualMachines/loginAsAdmin/action",
      "Microsoft.ContainerInstance/containerGroups/containers/exec/action",
      "Microsoft.Web/sites/config/list/action",
      "Microsoft.Web/sites/publishxml/action",
      "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",
    ]
  }

  assignable_scopes = [
    local.rg_ids["spoke_app"],
    local.rg_ids["test"],
  ]
}

# ---------------------------------------------------------------------------
# Identity used by the DeployIfNotExists policies (diagnostic settings, App
# Service basic auth). User-assigned and created here so that the roles it needs
# are granted by a human once, and CI never needs roleAssignments/write.
# ---------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "policy" {
  name                = "id-bastion-policy"
  resource_group_name = azurerm_resource_group.this["hub"].name
  location            = var.location
  tags                = local.tags
}

locals {
  # Roles named by the built-in definitions' roleDefinitionIds:
  #   Monitoring Contributor   749f88d5-cbae-40b8-bcfc-e573ddc772fa (blob diagnostic settings)
  #   Log Analytics Contributor 92aaf0da-9dab-42b6-94a3-d43ce8d16293 (all diagnostic settings)
  #   Website Contributor       de139f84-1756-47ae-9be6-808fbbe84772 (App Service basic auth)
  policy_roles = ["Monitoring Contributor", "Log Analytics Contributor", "Website Contributor"]
  policy_scopes = {
    hub       = local.rg_ids["hub"]
    spoke_app = local.rg_ids["spoke_app"]
    test      = local.rg_ids["test"]
  }
  policy_role_assignments = merge([
    for scope_key, scope in local.policy_scopes : {
      for role in local.policy_roles : "${scope_key}/${role}" => { scope = scope, role = role }
    }
  ]...)

  huginn_workspace_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.huginn_workspace.resource_group_name}/providers/Microsoft.OperationalInsights/workspaces/${var.huginn_workspace.name}"
}

resource "azurerm_role_assignment" "policy" {
  for_each = local.policy_role_assignments

  scope                            = each.value.scope
  role_definition_name             = each.value.role
  principal_id                     = azurerm_user_assigned_identity.policy.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Bastion policy remediation ${each.key}"
}

# The only write Bastion makes outside its own groups: a role assignment on Huginn's
# workspace so diagnostic settings can point at it. No resource in huginn-sentinel-rg
# changes. Turn off with grant_policy_identity_on_huginn_workspace = false.
resource "azurerm_role_assignment" "policy_huginn_workspace" {
  count = var.grant_policy_identity_on_huginn_workspace ? 1 : 0

  scope                            = local.huginn_workspace_id
  role_definition_name             = "Log Analytics Contributor"
  principal_id                     = azurerm_user_assigned_identity.policy.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Bastion policy identity: create diagnostic settings that send to law-huginn"
}
