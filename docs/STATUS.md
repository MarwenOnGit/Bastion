# Status

Nothing is "working" or "enforced" until a real run has proved it. This file records what
was actually checked, when, and how.

Last updated: 2026-11-03.

## Summary

| Area | State | Proven by |
|---|---|---|
| Terraform code, all 4 stacks | Written. `terraform validate` passes | GitHub Actions `ci` on `bastion-dev`, 2026-11-03 (real provider download) |
| Static checks (fmt, tflint with azurerm ruleset, checkov, conftest verify) | Pass | GitHub Actions `ci`, 2026-11-03 |
| pytest static checks, shellcheck | Pass locally; on GitHub once the docs commit lands | Build session, 2026-11-03 |
| Bootstrap applied | **No.** Waiting for you | |
| Governance applied (Audit mode) | **No** | |
| Network applied | **No** | |
| Workload applied | **No** | |
| Any control enforced (Deny) | **No.** Every control is in its audit effect | |
| Policy tests against Azure | **Not run.** Logic proven offline only, against a fake `az` | `tests/static/test_policy_scripts.py` |
| plan / apply / drift / policy-tests workflows | Written. Not run against Azure (no identities yet). `plan` correctly skips itself | GitHub Actions `plan` run 1, 2026-11-03 |

## Control status

| Control | Effect now | Applied | Policy test result |
|---|---|---|---|
| `storage_shared_key` | Audit | no | not run |
| `storage_public_network` | Audit | no | not run |
| `keyvault_public_network` | Audit | no | not run |
| `acr_admin_user` | Audit | no | not run |
| `appservice_basic_auth_audit` | AuditIfNotExists | no | n/a (compliance view) |
| `appservice_basic_auth_fix` | Disabled | no | n/a (remediation) |
| `nic_no_public_ip` | Audit | no | not run |
| `allowed_locations` | Audit | no | not run |
| `required_tags` | Audit | no | not run |
| `diagnostic_settings` | AuditIfNotExists | no | n/a (compliance view) |

## Verified in the build session (2026-11-03)

- All 16 built-in policy definitions in `policies/initiative.json`: GUID, display name,
  version, allowed effects and parameter names, against github.com/Azure/azure-policy
  commit `f096d8d` (2026-10-28). Microsoft Learn was not reachable from the session.
- GitHub numeric IDs: owner `183097322`, repository `1444942400` (GitHub search API).
- Action SHAs, resolved with `git ls-remote` against the tags: `actions/checkout` v7.0.1,
  `hashicorp/setup-terraform` v4.0.1, `azure/login` v3.1.0 (annotated tag, commit SHA
  used), `actions/setup-python` v7.1.0.
- tflint 0.55.0 and conftest 0.58.0 release archives: SHA-256 recorded in the workflows.
- `conftest verify`: 24 of 24 rule tests pass.
- checkov 3.4.3: 54 passed, 0 failed, 11 skipped, each skip justified in the code.

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

## Decisions taken without your answer (you asked for an end-to-end build)

| Question | Default chosen | Change it in |
|---|---|---|
| Budget amount | $20 a month | `budget_amount`, `infra/governance/variables.tf` |
| Budget email | Not committed. Repository variable `BUDGET_ALERT_EMAIL` | GitHub variables |
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
| | 6 | Waiting for Audit results from a real apply |
