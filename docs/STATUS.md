# Status

Nothing is "working" or "enforced" until a real run has proved it. This file records what
was actually checked, when, and how.

Last updated: 2026-11-04.

## Summary

| Area | State | Proven by |
|---|---|---|
| Terraform code, all 4 stacks | Written. `terraform validate` passes | GitHub Actions `ci` on `bastion-dev`, 2026-11-03 (real provider download) |
| Static checks (fmt, tflint with azurerm ruleset, checkov, conftest verify) | Pass | GitHub Actions `ci`, 2026-11-03 |
| pytest static checks, shellcheck | Pass | GitHub Actions `ci`, 2026-11-03; locally after every change |
| Bootstrap applied | **No.** Waiting for you | |
| Governance applied (Audit mode) | **No** | |
| Network applied | **No** | |
| Workload applied | **No** | |
| Any control enforced (Deny) | **No.** Every control is in its audit effect | |
| Policy tests against Azure | **Not run.** Logic proven offline only, against a fake `az` | `tests/static/test_policy_scripts.py` |
| plan / apply / drift / policy-tests workflows | Written. Not run against Azure (no identities yet). `plan` correctly skips itself | GitHub Actions `plan` run 1, 2026-11-03 |

## Control status

| Control | Effect now | Target | Applied | Policy test result |
|---|---|---|---|---|
| `storage_shared_key` | Audit | Deny | no | not run |
| `storage_public_network` | Audit | Deny | no | not run |
| `keyvault_public_network` | Audit | Deny | no | not run |
| `acr_admin_user` | Audit | Deny | no | not run |
| `appservice_basic_auth_audit` | AuditIfNotExists | AuditIfNotExists | no | n/a (compliance report) |
| `appservice_basic_auth_fix` | Disabled | DeployIfNotExists | no | n/a (compliance report) |
| `nic_no_public_ip` | Audit | Deny | no | not run |
| `allowed_locations` | Audit | Deny | no | not run |
| `required_tags` | Audit | Deny | no | not run |
| `diagnostic_settings` | AuditIfNotExists | DeployIfNotExists | no | n/a (compliance report) |
| `storage_secure_transfer` | Audit | Deny | no | not run |
| `storage_min_tls` | Audit | Deny | no | not run |
| `storage_blob_public_access` | Audit | Deny | no | not run |
| `keyvault_rbac` | Audit | Deny | no | not run |
| `keyvault_purge_protection` | Audit | Deny | no | not run |
| `subnet_private` | Audit | Deny | no | not run |
| `subnet_nsg` | Audit | Deny | no | not run |
| `mgmt_ports_internet` | Audit | Deny | no | not run |
| `denied_resource_types` | Audit | Deny | no | not run |
| `protect_diagnostic_settings` | Disabled | DenyAction | no | manual check, not done |
| `delete_protection` | Disabled | DenyAction | no | not run |

## Verified in the build session (2026-11-03 and 2026-11-04)

- All 23 built-in policy definitions in `policies/initiative.json`: GUID, display name,
  version, allowed effects and parameter names, against github.com/Azure/azure-policy
  commit `f096d8d` (2026-10-28). learn.microsoft.com was not reachable from the session.
- MCSB groups of every built-in, from the Microsoft cloud security benchmark v2
  initiative (`e3ec7e09-768c-4b64-882c-fcada3772047` v1.8.0) in the same commit.
- Azure Landing Zones assignments and definitions compared, and three definitions copied
  with MIT attribution, from Azure/Azure-Landing-Zones-Library commit `124b242`
  (2026-10-20).
- Microsoft Learn statements used in the ADRs, read from the docs source repositories on
  2026-11-04 (MicrosoftDocs/azure-docs, cloud-adoption-framework, azure-monitor-docs,
  azure-dev-docs, entra-docs): denyAction supports only `delete`; `DoNotEnforce` writes no
  Activity log entry; customer-managed deny assignments are private preview; deployment
  stack deny settings are `DenyDelete` and `DenyWriteAndDelete`; Policy events in the
  Activity log carry the assignment in `properties.policies`; budgets are supported at
  subscription scope; CAF's single-subscription scenario.
- Provider versions resolved by GitHub Actions on 2026-11-03: azurerm 4.81.0, azuread
  3.10.0, local 2.9.1. Pinned to `~> 4.81`, `~> 3.10`, `~> 2.9`. Inline `subnet` blocks
  with `security_group` checked in the azurerm v4.81.0 documentation.
- GitHub numeric IDs: owner `183097322`, repository `1444942400` (GitHub search API).
- Action SHAs, resolved with `git ls-remote` against the tags: `actions/checkout` v7.0.1,
  `hashicorp/setup-terraform` v4.0.1, `azure/login` v3.1.0 (annotated tag, commit SHA
  used), `actions/setup-python` v7.1.0.
- tflint 0.55.0 and conftest 0.58.0 release archives: SHA-256 recorded in the workflows.
- `conftest verify`: 36 of 36 rule tests pass.
- checkov 3.4.3: 54 passed, 0 failed, 12 skipped, each skip justified in the code.
- pytest: every policy test script passes only on its own policy's denial, fails on any
  other, and deletes what was wrongly created, against a fake `az` (offline).

## Could not verify in the build session (verify in Azure)

- Whether Azure Cost Management budgets are available on this Azure for Students
  subscription. If the governance apply fails on the budget, the error will say so.
- Whether an Azure for Students subscription can be moved under a management group (ADR
  0001). Not attempted by default.
- That `azurerm_storage_account` with public network access disabled can be created and
  refreshed from a GitHub runner without data-plane access (azurerm 4.x is expected to
  manage it through ARM only).
- That `not_scopes` accepts a resource group that does not exist yet.
- That the NIC policy test gets `RequestDisallowedByPolicy` before the network provider
  rejects the fake subnet and public IP references (ARM evaluates policy first, so it
  should).
- That disabling SCM basic auth makes Kudu `/api/command` with publishing credentials fail
  (X-11).
- Ingestion cost of Bastion's diagnostic logs in `law-huginn`.
- Prices in COST.md and ADR 0007 (from memory; pricing pages were not reachable).
- That Reader is enough for `az policy state summarize` and `list` (the compliance report
  runs as the plan identity). Microsoft.PolicyInsights exposes these as read operations.
- The exact error a DenyAction refusal returns (Learn says HTTP 403). The delete-protection
  test accepts a 403 or "denyAction" text that names `bastion-baseline`.
- That `protect_diagnostic_settings` (mode `Indexed`, as in ALZ) evaluates
  `Microsoft.Insights/diagnosticSettings`, which has no location or tags.
- That Defender for Cloud's own default assignment (the Microsoft cloud security benchmark
  at subscription scope) exists on this subscription. Bastion does not assign MCSB itself.
- The KQL in PREVENT-DETECT against `law-huginn` (field layout of `Properties_d`).
- That Bastion Diagnostics Destination (`workspaces/read` + `workspaces/sharedKeys/action`)
  is enough for a DeployIfNotExists remediation to create a diagnostic setting that sends
  to `law-huginn`. Learn documents it for users configuring diagnostic settings; the
  policy deployment path is not described separately. Fallback:
  `narrow_huginn_workspace_role = false`.
- That Monitoring Contributor alone (without the Log Analytics Contributor the Key Vault
  and NSG built-ins list in `roleDefinitionIds`) lets the remediation deploy. Fallback:
  `policy_identity_log_analytics_contributor = true`.
- That Azure Policy checks `userAssignedIdentities/assign/action` when a policy
  assignment references a user-assigned identity. Learn states the rule for assigning a
  user-assigned identity to any resource; it is not stated for policy assignments in
  particular. If it is not checked, the custom role is harmless and can be removed.
- Which Huginn operations the `CanNotDelete` lock on `law-huginn` blocks besides deleting
  the workspace (Learn: extension resources inherit the lock).
- That the three custom apply roles (Bastion Policy Author, Policy Assigner, Defender
  Settings) cover every call the governance plan makes. Microsoft does not publish a
  per-call list; an `AuthorizationFailed` error names any missing action.
- Whether Bastion Policy Assigner is enough to start a remediation task by hand. It is
  not meant to be: remediation tasks need `Microsoft.PolicyInsights/remediations/write`,
  which apply no longer has. Start them as yourself.

## Blocked in the build session

| What | Host | Effect | Workaround used |
|---|---|---|---|
| Terraform provider registry | `registry.terraform.io` | `terraform init` / `validate` impossible locally | None, as asked. Validation runs in GitHub Actions `ci`, which passed |
| tflint azurerm ruleset install | `api.github.com` (release metadata) | Local tflint ran with the core ruleset only | None. GitHub `ci` runs the azurerm ruleset |
| Microsoft Learn | `learn.microsoft.com` | Policy IDs could not be checked there | Checked against the azure-policy source repository instead |
| Push to `main` | refused by the session's permission policy | `main` does not exist | You create it (SETUP step 0) |

## Corrections to the original brief

| # | Brief said | What is true | Change made |
|---|---|---|---|
| 1 | Every policy starts in Audit | Two built-ins (NIC public IP `83a86a26...`, Require a tag `871b6d14...`) have the effect fixed to Deny | Custom copies with an effect parameter (ADR 0003) |
| 2 | App Service basic auth: Deny or Modify | Built-ins exist only as AuditIfNotExists and DeployIfNotExists | Two controls: audit, and DeployIfNotExists fix (starts Disabled) |
| 3 | DeployIfNotExists for diagnostic settings | These built-ins also allow AuditIfNotExists | Starts in AuditIfNotExists |
| 4 | CI never holds User Access Administrator | DeployIfNotExists needs role assignments for its identity, and the custom role needs `roleDefinitions/write` | User-assigned policy identity, its roles and the custom role are all created by the bootstrap |
| 5 | Diagnostic settings to `law-huginn` | The built-ins say a workspace outside the assignment scope needs Log Analytics Contributor granted by hand | Bootstrap grants it on `law-huginn` only (toggle `grant_policy_identity_on_huginn_workspace`) |
| 6 | Management groups in the governance stack | The creator of a management group becomes its Owner | Created in the bootstrap, so no CI identity owns anything |
| 7 | Exclude "any group starting with ctf-" | `not_scopes` has no wildcards | Existing `ctf-` groups must be listed; the only subscription assignment is audit-only (ADR 0002) |
| 8 | Scheduled drift and policy tests | Scheduled workflows run on the default branch | Plan identity trusts `main`; both run after merge |
| 9 | "Read-only plus state access" for plan | A state lock is a blob lease (a write) | Plans run with `-lock=false`; the plan identity only reads state |
| 10 | (not in brief) | azurerm 4.x registers resource providers by default, which CI cannot | CI stacks set `resource_provider_registrations = "none"`; bootstrap registers them |
| 11 | Workload cost "free where possible" | 2 private endpoints cost about $14.60 a month | Workload is designed to be applied for demos and destroyed (COST.md) |
| 12 | Plan on pull requests (to be decided) | Safe: identity is read-only, forks get no OIDC token | Enabled |
| 13 | "Azure Policy cannot block actions" | Policy's `denyAction` effect blocks `delete` (and only `delete`) | Two DenyAction controls; the wording in every doc now says "Deny judges create and update, DenyAction only delete" |
| 14 | "Real deny on Run Command with deployment stacks" (my roadmap, 2026-11-03) | Stack deny settings are only `DenyDelete` and `DenyWriteAndDelete`; customer-managed deny assignments are private preview | Removed from the roadmap; ADR 0008 corrected |
| 15 | (my design, 2026-11-03) Subnets as separate `azurerm_subnet` resources | A subnet created before its NSG association violates ALZ's Deny-Subnet-Without-Nsg | Subnets declared inline with `security_group` |
| 16 | (my code, 2026-11-03) `enable_rbac_authorization` on Key Vault | Deprecated in azurerm 4.x, removed in 5.0 | `rbac_authorization_enabled` |
| 17 | (my code, 2026-11-03) Providers `~> 4.0` and no lock files | Too loose; HashiCorp recommends committed lock files | Pinned to the minor version CI resolved; SETUP step to create and commit lock files |
| 18 | (security review 1, high) Apply had Contributor on `bastion-hub-rg`, where `id-bastion-policy` lived, so it could attach the identity to new compute and run code as it; the identity had Log Analytics Contributor (`Microsoft.OperationalInsights/*`) on `law-huginn` | Attaching a user-assigned identity needs `assign/action` on it (Learn, managed identities FAQ); Contributor includes it | Identity moved to `bastion-identity-rg` (no CI Contributor); apply gets only read + `assign/action` on the identity (custom role); identity-carrying compute denied; conftest rule; destination-only role on `law-huginn`; `CanNotDelete` lock on `law-huginn` |
| 19 | (security review 1c) Log Analytics Contributor on the Bastion groups, as the diagnostic built-ins list it | It brings `virtualMachines/extensions/*` and `listKeys`; Monitoring Contributor already has `DiagnosticSettings/*` and `deployments/*` (Learn, built-in roles for Monitor) | Monitoring Contributor only, behind `policy_identity_log_analytics_contributor` (default false) |
| 20 | (my docs) ADR 0006 called the `law-huginn` role "the one role assignment Bastion makes in huginn-sentinel-rg" | There are now two writes there: the role assignment and the lock | Reworded in ADR 0006 and in `roles.tf` |
| 21 | (security review 2, medium) Apply had Resource Policy Contributor at subscription scope | It covers assignments, exemptions and remediation everywhere in the subscription | Custom roles: Bastion Policy Author (definitions, subscription) and Bastion Policy Assigner (assignments, Bastion groups only; subscription only with `allow_subscription_audit_assignment`) |
| 22 | (security review 2, medium) Apply had Security Admin at subscription scope | It covers all of `Microsoft.Security/*`, and also `policyAssignments/*` at subscription scope (Learn, built-in roles for Security) | Custom role Bastion Defender Settings: `pricings/{read,write}`, `securityContacts/{read,write,delete}` |
| 23 | (security review 3, low) Budget email as a repository variable, in job-level `env` | GitHub Docs: variables render unmasked in logs, and job `env` is printed in every step header of these public logs; Terraform did not mark it sensitive | Actions secret, read only by the step that builds `TF_VAR_budget_alert_emails` (which masks it); `sensitive = true` on `budget_alert_emails`, which also feeds the security contact |
| 24 | (security review 4, docs) README, blog, ALZ-ALIGNMENT and ARCHITECTURE listed "management groups" first under governance, which reads as management-group-level governance | Nothing is assigned to a management group and the subscription is not under the hierarchy | Each now says: policy is assigned at resource group scope; the management group hierarchy is prepared but empty until ADR 0001's check is done |

## Decisions taken without your answer (you asked for an end-to-end build)

| Question | Default chosen | Change it in |
|---|---|---|
| Budget amount | $20 a month | `budget_amount`, `infra/governance/variables.tf` |
| Budget email | Not committed. Actions secret `BUDGET_ALERT_EMAIL` (was a variable until 2026-11-04) | GitHub secrets |
| Region | `francecentral` | `location` in each stack |
| Workload always on? | No: apply for demos, destroy after | COST.md |
| Role on `law-huginn` for the policy identity | Yes | `grant_policy_identity_on_huginn_workspace` |
| Plan on pull requests | Yes | `plan_on_pull_requests` |
| Local provider mirror for validation | Not used (no workarounds) | n/a |
| Branch | `bastion-dev`, as in the brief | |

## Phase log

| Date | Phase | What happened |
|---|---|---|
| 2026-11-03 | 0 | Plan and questions. Tools installed. Huginn inventory read |
| 2026-11-03 | 1 to 5, 7 | Bootstrap, governance, network, workload, conftest rules, policy tests, workflows and docs written on `bastion-dev`. Nothing applied |
| 2026-11-04 | review | Compared with Azure Landing Zones, MCSB v2 and Microsoft Learn. 11 controls added, network made Deny-compatible, compliance report added, ADRs 0003, 0004, 0007, 0008 revised, ADR 0009 and ALZ-ALIGNMENT added, blog post written. Nothing applied |
| | 6 | Waiting for Audit results from a real apply |
