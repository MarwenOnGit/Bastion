# ---------------------------------------------------------------------------
# bastion-baseline: definitions, initiative and assignments.
#
# Single source of truth:
#   policies/initiative.json        which definitions, which parameters
#   policies/definitions/*.json     the two custom definitions
#   policies/effects.json           the current effect of each control
#
# Definitions and the initiative live at subscription scope (an assignment at a
# resource group needs its definition at that subscription or above).
# Assignments with real effects are made ONLY at the Bastion resource groups.
# ---------------------------------------------------------------------------

locals {
  policy_root = "${path.module}/../../policies"

  initiative = jsondecode(file("${local.policy_root}/initiative.json"))
  effects    = { for k, v in jsondecode(file("${local.policy_root}/effects.json")) : k => v if !startswith(k, "_") }

  custom_definition_files = fileset("${local.policy_root}/definitions", "*.json")
  custom_definitions = {
    for f in local.custom_definition_files :
    jsondecode(file("${local.policy_root}/definitions/${f}")).name => jsondecode(file("${local.policy_root}/definitions/${f}"))
  }

  controls = { for c in local.initiative.controls : c.control => c }

  members = flatten([
    for c in local.initiative.controls : [
      for m in c.members : merge(m, { control = c.control })
    ]
  ])

  # One effect parameter per control, plus the extra shared parameters.
  initiative_parameters = merge(
    {
      for c in local.initiative.controls : "effect_${c.control}" => {
        type          = "String"
        allowedValues = c.allowedEffects
        defaultValue  = c.auditEffect
        metadata = {
          displayName = "Effect: ${c.title}"
          description = "Target effect: ${c.targetEffect}. ${c.why}"
        }
      }
    },
    local.initiative.extraParameters
  )

  # Controls whose entry in effects.json is missing or not an allowed effect.
  invalid_effects = [
    for k, c in local.controls : k if !contains(c.allowedEffects, lookup(local.effects, k, "missing"))
  ]

  assignment_parameters = merge(
    { for k, v in local.effects : "effect_${k}" => { value = v } },
    {
      listOfAllowedLocations        = { value = var.allowed_locations }
      logAnalyticsWorkspaceId       = { value = var.huginn_workspace_id }
      listOfResourceTypesNotAllowed = { value = var.denied_resource_types }
    }
  )

  # Subscription scope: every control forced to its audit effect, whatever effects.json says.
  audit_only_parameters = merge(
    { for k, c in local.controls : "effect_${k}" => { value = c.auditEffect } },
    {
      listOfAllowedLocations        = { value = var.allowed_locations }
      logAnalyticsWorkspaceId       = { value = var.huginn_workspace_id }
      listOfResourceTypesNotAllowed = { value = var.denied_resource_types }
    }
  )

  policy_identity_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.policy_identity_resource_group}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${var.policy_identity_name}"

  protected_scopes = [
    for rg in concat(var.protected_resource_groups, var.existing_prefixed_protected_groups) :
    "/subscriptions/${var.subscription_id}/resourceGroups/${rg}"
  ]
}

resource "azurerm_policy_definition" "custom" {
  for_each = local.custom_definitions

  name         = each.key
  policy_type  = "Custom"
  mode         = each.value.properties.mode
  display_name = each.value.properties.displayName
  description  = each.value.properties.description
  metadata     = jsonencode(each.value.properties.metadata)
  parameters   = jsonencode(each.value.properties.parameters)
  policy_rule  = jsonencode(each.value.properties.policyRule)
}

resource "azurerm_policy_set_definition" "baseline" {
  name         = local.initiative.name
  policy_type  = "Custom"
  display_name = local.initiative.displayName
  description  = local.initiative.description
  metadata     = jsonencode(local.initiative.metadata)
  parameters   = jsonencode(local.initiative_parameters)

  dynamic "policy_definition_reference" {
    for_each = local.members
    content {
      reference_id = policy_definition_reference.value.referenceId
      policy_definition_id = (
        startswith(policy_definition_reference.value.definition, "builtin:")
        ? "/providers/Microsoft.Authorization/policyDefinitions/${trimprefix(policy_definition_reference.value.definition, "builtin:")}"
        : azurerm_policy_definition.custom[trimprefix(policy_definition_reference.value.definition, "custom:")].id
      )
      parameter_values = jsonencode({
        for k, v in policy_definition_reference.value.parameters : k => { value = v }
      })
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.invalid_effects) == 0
      error_message = "policies/effects.json has a missing or disallowed effect for: ${join(", ", local.invalid_effects)}."
    }
  }
}

data "azurerm_resource_group" "assigned" {
  for_each = toset(var.assignment_resource_groups)
  name     = each.value
}

resource "azurerm_resource_group_policy_assignment" "baseline" {
  for_each = data.azurerm_resource_group.assigned

  name                 = "bastion-baseline"
  display_name         = "Bastion baseline (${each.key})"
  description          = "bastion-baseline with the effects in policies/effects.json. Managed by infra/governance."
  resource_group_id    = each.value.id
  policy_definition_id = azurerm_policy_set_definition.baseline.id
  location             = var.location
  parameters           = jsonencode(local.assignment_parameters)
  enforce              = true

  identity {
    type         = "UserAssigned"
    identity_ids = [local.policy_identity_id]
  }

  non_compliance_message {
    content = "Blocked or flagged by the Bastion landing zone baseline. See docs/POLICIES.md in github.com/MarwenOnGit/Bastion."
  }

  metadata = jsonencode({ managedBy = "infra/governance", project = "bastion" })
}

# Optional: report-only view of the whole subscription. Every effect is its audit
# effect, and every protected group is excluded, so this cannot block or change
# anything in the Huggin, Fenrir or CTF groups. The policy identity only has roles
# on Bastion groups, so even a misconfigured DeployIfNotExists could not deploy
# anywhere else.
resource "azurerm_subscription_policy_assignment" "audit_only" {
  count = var.enable_subscription_audit ? 1 : 0

  name                 = "bastion-baseline-audit"
  display_name         = "Bastion baseline (subscription, audit only)"
  description          = "Report-only. Protected groups excluded."
  subscription_id      = "/subscriptions/${var.subscription_id}"
  policy_definition_id = azurerm_policy_set_definition.baseline.id
  location             = var.location
  parameters           = jsonencode(local.audit_only_parameters)
  not_scopes           = local.protected_scopes
  enforce              = true

  identity {
    type         = "UserAssigned"
    identity_ids = [local.policy_identity_id]
  }

  metadata = jsonencode({ managedBy = "infra/governance", project = "bastion", mode = "audit-only" })
}
