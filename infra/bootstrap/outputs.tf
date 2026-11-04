locals {
  bootstrap = {
    generated_by    = "infra/bootstrap"
    tenant_id       = var.tenant_id
    subscription_id = var.subscription_id
    location        = var.location
    resource_groups = local.resource_groups
    tfstate = {
      resource_group_name  = azurerm_resource_group.this["tfstate"].name
      storage_account_name = azurerm_storage_account.tfstate.name
      container_name       = local.tfstate_container_name
    }
    identities = {
      for k, app in azuread_application.ci : k => {
        display_name = app.display_name
        client_id    = app.client_id
        object_id    = azuread_service_principal.ci[k].object_id
      }
    }
    federated_subjects = { for k, c in azuread_application_federated_identity_credential.ci : k => c.subject }
    policy_identity = {
      id           = azurerm_user_assigned_identity.policy.id
      principal_id = azurerm_user_assigned_identity.policy.principal_id
      client_id    = azurerm_user_assigned_identity.policy.client_id
    }
    custom_roles = merge(
      {
        vm_operator               = azurerm_role_definition.vm_operator.role_definition_resource_id
        policy_identity_reference = azurerm_role_definition.policy_identity_reference.role_definition_resource_id
        policy_author             = azurerm_role_definition.policy_author.role_definition_resource_id
        policy_assigner           = azurerm_role_definition.policy_assigner.role_definition_resource_id
        defender_settings         = azurerm_role_definition.defender_settings.role_definition_resource_id
      },
      { for r in azurerm_role_definition.diagnostics_destination : "diagnostics_destination" => r.role_definition_resource_id }
    )
    huginn_workspace_locked = var.lock_huginn_workspace
    management_groups = merge(
      { bastion = azurerm_management_group.bastion.id },
      { for k, mg in azurerm_management_group.child : k => mg.id }
    )
    huginn_workspace_id = local.huginn_workspace_id
  }
}

# Non-secret IDs that the other stacks, the workflows and docs/SETUP.md use.
# Commit this file after the first apply.
resource "local_file" "bootstrap_json" {
  filename        = "${path.module}/../shared/bootstrap.json"
  content         = "${jsonencode(local.bootstrap)}\n"
  file_permission = "0644"
}

output "bootstrap" {
  description = "Non-secret IDs. Also written to infra/shared/bootstrap.json."
  value       = local.bootstrap
}

output "github_variables" {
  description = "Repository variables to create in GitHub (Settings > Secrets and variables > Actions > Variables)."
  value = {
    AZURE_TENANT_ID         = var.tenant_id
    AZURE_SUBSCRIPTION_ID   = var.subscription_id
    AZURE_PLAN_CLIENT_ID    = azuread_application.ci["plan"].client_id
    AZURE_APPLY_CLIENT_ID   = azuread_application.ci["apply"].client_id
    AZURE_TESTER_CLIENT_ID  = azuread_application.ci["policy_tester"].client_id
    TFSTATE_STORAGE_ACCOUNT = azurerm_storage_account.tfstate.name
  }
}
