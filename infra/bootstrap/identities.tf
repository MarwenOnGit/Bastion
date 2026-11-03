# ---------------------------------------------------------------------------
# GitHub Actions identities. App registrations with federated credentials only:
# no client secret and no certificate is ever created.
#
# Subjects use the ID-based format this tenant expects:
#   repo:<owner>@<owner_id>/<repo>@<repo_id>:<context>
# Name-only subjects (repo:<owner>/<repo>:...) fail with AADSTS700213.
# ---------------------------------------------------------------------------

locals {
  github_issuer   = "https://token.actions.githubusercontent.com"
  github_audience = "api://AzureADTokenExchange"
  subject_prefix  = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"

  plan_subjects = merge(
    { for b in var.plan_branches : "branch-${b}" => "${local.subject_prefix}:ref:refs/heads/${b}" },
    var.plan_on_pull_requests ? { "pull-request" = "${local.subject_prefix}:pull_request" } : {}
  )

  ci_identities = {
    plan = {
      display_name = "bastion-github-plan"
      description  = "Bastion CI: terraform plan and drift detection. Read-only on Azure, read-only on state."
      subjects     = local.plan_subjects
    }
    apply = {
      display_name = "bastion-github-apply"
      description  = "Bastion CI: terraform apply. Trusted only for jobs in the bastion-apply GitHub environment."
      subjects     = { "env-bastion-apply" = "${local.subject_prefix}:environment:bastion-apply" }
    }
    policy_tester = {
      display_name = "bastion-policy-tester"
      description  = "Bastion CI: policy tests. Contributor on bastion-test-rg only. Trusted only for the bastion-policy-tests environment."
      subjects     = { "env-bastion-policy-tests" = "${local.subject_prefix}:environment:bastion-policy-tests" }
    }
  }

  federated_credentials = merge([
    for id_key, id in local.ci_identities : {
      for cred_key, subject in id.subjects : "${id_key}/${cred_key}" => {
        identity = id_key
        name     = "github-${cred_key}"
        subject  = subject
      }
    }
  ]...)
}

resource "azuread_application" "ci" {
  for_each = local.ci_identities

  display_name     = each.value.display_name
  description      = each.value.description
  owners           = [data.azuread_client_config.current.object_id]
  sign_in_audience = "AzureADMyOrg"

  tags = ["bastion", "github-actions", "oidc-only"]
}

resource "azuread_service_principal" "ci" {
  for_each = local.ci_identities

  client_id                    = azuread_application.ci[each.key].client_id
  owners                       = [data.azuread_client_config.current.object_id]
  app_role_assignment_required = false
  description                  = each.value.description

  tags = ["bastion", "github-actions", "oidc-only"]
}

resource "azuread_application_federated_identity_credential" "ci" {
  #checkov:skip=CKV_AZURE_249:Subjects are built from variables, so checkov cannot read them, and its repo regex rejects ID-based subjects. tests/static/test_oidc.py checks that every subject is ID-based and pinned to a branch, an environment or pull_request.
  for_each = local.federated_credentials

  application_id = azuread_application.ci[each.value.identity].id
  display_name   = each.value.name
  description    = "GitHub Actions OIDC, ID-based subject"
  audiences      = [local.github_audience]
  issuer         = local.github_issuer
  subject        = each.value.subject
}
