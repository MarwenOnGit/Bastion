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
#
# It lives in its own resource group, bastion-identity-rg, where no CI identity has
# Contributor. The apply identity only gets "Bastion Policy Identity Reference" on
# the identity itself (read + assign/action), which is what attaching it to a policy
# assignment requires. See docs/adr/0006 for why that right is still dangerous, and
# how the denied_resource_types control and the conftest rule limit it.
# ---------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "policy" {
  name                = "id-bastion-policy"
  resource_group_name = azurerm_resource_group.this["identity"].name
  location            = var.location

  # bastion-protected = true: the delete_protection control (DenyAction) blocks deleting
  # it once that control is on. Destroy the governance stack before the bootstrap.
  tags = merge(local.tags, { "bastion-protected" = "true" })
}

# Microsoft Learn (managed identities FAQ): assigning a user-assigned identity to a
# resource needs Microsoft.ManagedIdentity/userAssignedIdentities/*/assign/action on
# the identity. A policy assignment with identity.type = UserAssigned is such a resource.
resource "azurerm_role_definition" "policy_identity_reference" {
  name        = "Bastion Policy Identity Reference"
  scope       = local.subscription_scope
  description = "Read id-bastion-policy and attach it to a policy assignment. Nothing else. Assigned on the identity resource only."

  permissions {
    actions = [
      "Microsoft.ManagedIdentity/userAssignedIdentities/read",
      "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",
    ]
  }

  # Learn recommends resource groups, not single resources, as assignable scopes.
  # The assignment below is made on the identity resource itself.
  assignable_scopes = [local.rg_ids["identity"]]
}

resource "azurerm_role_assignment" "apply_policy_identity_reference" {
  scope                            = azurerm_user_assigned_identity.policy.id
  role_definition_id               = azurerm_role_definition.policy_identity_reference.role_definition_resource_id
  principal_id                     = azuread_service_principal.ci["apply"].object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Bastion apply: attach id-bastion-policy to bastion-baseline assignments"
}

locals {
  # On the Bastion groups the identity needs to deploy diagnostic settings and to
  # change App Service publishing settings.
  #   Monitoring Contributor 749f88d5-cbae-40b8-bcfc-e573ddc772fa: includes
  #     Microsoft.Insights/DiagnosticSettings/* and Microsoft.Resources/deployments/*,
  #     which is what a DeployIfNotExists diagnostic-settings deployment does.
  #   Website Contributor de139f84-1756-47ae-9be6-808fbbe84772: App Service basic auth fix.
  # The KV and NSG diagnostic built-ins name Log Analytics Contributor in their
  # roleDefinitionIds; that role also brings Microsoft.Compute/virtualMachines/extensions/*
  # and Microsoft.Storage/storageAccounts/listKeys/action, so it is off by default
  # (policy_identity_log_analytics_contributor). See docs/STATUS.md, Could not verify.
  policy_roles = concat(
    ["Monitoring Contributor", "Website Contributor"],
    var.policy_identity_log_analytics_contributor ? ["Log Analytics Contributor"] : []
  )
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
  huginn_rg_id        = "/subscriptions/${var.subscription_id}/resourceGroups/${var.huginn_workspace.resource_group_name}"
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

# ---------------------------------------------------------------------------
# Huginn's workspace. Bastion makes two writes outside its own groups, both here:
# a role assignment and a delete lock on law-huginn. No setting of the workspace
# itself changes.
# ---------------------------------------------------------------------------

# Microsoft Learn ("Manage access to Log Analytics workspaces", example 3):
# workspaces/read + workspaces/sharedKeys/action let a principal "only enumerate the
# workspace and use it as a destination for diagnostic settings". It cannot query,
# configure or delete the workspace. The shared keys it can read do allow sending data
# to the workspace; that residual risk is in docs/PREVENT-DETECT.md.
resource "azurerm_role_definition" "diagnostics_destination" {
  count = var.grant_policy_identity_on_huginn_workspace && var.narrow_huginn_workspace_role ? 1 : 0

  name        = "Bastion Diagnostics Destination"
  scope       = local.subscription_scope
  description = "Use a Log Analytics workspace as a diagnostic settings destination. No query, no configuration, no delete."

  permissions {
    actions = [
      "Microsoft.OperationalInsights/workspaces/read",
      "Microsoft.OperationalInsights/workspaces/sharedKeys/action",
    ]
  }

  assignable_scopes = [local.huginn_rg_id]
}

resource "azurerm_role_assignment" "policy_huginn_workspace" {
  count = var.grant_policy_identity_on_huginn_workspace ? 1 : 0

  scope                            = local.huginn_workspace_id
  role_definition_name             = var.narrow_huginn_workspace_role ? null : "Log Analytics Contributor"
  role_definition_id               = var.narrow_huginn_workspace_role ? azurerm_role_definition.diagnostics_destination[0].role_definition_resource_id : null
  principal_id                     = azurerm_user_assigned_identity.policy.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Bastion policy identity: use law-huginn as a diagnostic settings destination"
}

# CanNotDelete lock on law-huginn. Nothing in Bastion, and nobody else, can delete the
# workspace while it exists, including Huginn's own Terraform. Extension resources
# inherit a lock from the resource they are applied to (Microsoft Learn, "Lock your
# resources"), so deleting resources scoped on the workspace may be blocked too.
# Remove it by setting lock_huginn_workspace = false and applying the bootstrap.
resource "azurerm_management_lock" "huginn_workspace" {
  count = var.lock_huginn_workspace ? 1 : 0

  name       = "bastion-protect-law-huginn"
  scope      = local.huginn_workspace_id
  lock_level = "CanNotDelete"
  notes      = "Set by the Bastion bootstrap (lock_huginn_workspace). Blocks deleting law-huginn, also from the Huginn repo, until it is removed. See Bastion docs/SETUP.md."
}
