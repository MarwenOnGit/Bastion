output "initiative_id" {
  description = "ID of the bastion-baseline policy set definition."
  value       = azurerm_policy_set_definition.baseline.id
}

output "assignment_ids" {
  description = "Policy assignment IDs per Bastion resource group."
  value       = { for k, a in azurerm_resource_group_policy_assignment.baseline : k => a.id }
}

output "current_effects" {
  description = "Effect of each control, from policies/effects.json."
  value       = local.effects
}
