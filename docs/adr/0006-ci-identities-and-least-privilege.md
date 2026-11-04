# ADR 0006: CI identities and least privilege

Date: 2026-11-03, revised 2026-11-04 (security review). Status: accepted.

## Decision

Three app registrations, created by the bootstrap that you run, never by CI.

### bastion-github-plan (plan and drift)

| Role | Scope | Why |
|---|---|---|
| Reader | subscription | Refresh every resource in the plan, including policy and budget |
| Storage Blob Data Reader | `tfstate` container | Read state |

Plans run with `-lock=false`. Taking a state lock is a blob lease, which is a write. A
read-only identity cannot take it, and a plan that does not apply has nothing to protect.

### bastion-github-apply (apply)

| Role | Scope | Why |
|---|---|---|
| Reader | subscription | Read data sources (resource groups, DNS zones, subnets) |
| Resource Policy Contributor | subscription | Policy definitions, the initiative and assignments |
| Cost Management Contributor | subscription | The budget |
| Security Admin | subscription | The Defender for Cloud free tier setting |
| Contributor | `bastion-hub-rg`, `bastion-spoke-app-rg` | Network and workload resources |
| Bastion Policy Identity Reference (custom) | the `id-bastion-policy` resource only | Attach the policy identity to `bastion-baseline` assignments |
| Storage Blob Data Contributor | `tfstate` container | Write state and take locks |

Residual risk, stated plainly:

- Resource Policy Contributor at subscription scope could create a Deny assignment on a
  protected group. Three layers stop that from happening by accident: the Terraform
  variable validation, the conftest rule run before every apply, and your review in the
  `bastion-apply` environment. None of them stops a malicious workflow change merged to
  main; your review of the pull request does.
- Security Admin could enable a paid Defender plan. conftest rejects any tier other than
  Free.

### bastion-policy-tester (policy tests)

| Role | Scope |
|---|---|
| Contributor | `bastion-test-rg` |

Nothing else. It cannot read or change any other group.

### What no CI identity has

- No Owner, User Access Administrator or Role Based Access Control Administrator, at any
  scope. CI can never create a role assignment, so it can never grant itself more.
- No Microsoft Graph permission. App registrations and federated credentials are changed
  only by the bootstrap.
- No rights on the protected groups (Huginn, Fenrir, CTF), apart from Reader at
  subscription scope, which every read-only plan needs.

### Things moved into the bootstrap because of this

| Item | Right it needs |
|---|---|
| Resource groups | `resourceGroups/write` at subscription scope |
| Custom role "Bastion VM Operator" | `roleDefinitions/write` |
| Policy identity `id-bastion-policy`, its resource group and its roles | `roleAssignments/write` |
| Delete lock on `law-huginn` | `Microsoft.Authorization/locks/write` (Owner) |
| Management groups | the creator becomes Owner of each group |
| Resource provider registration | `register/action` at subscription scope |

### Policy identity: id-bastion-policy

A user-assigned identity used by every DeployIfNotExists member. It lives alone in
`bastion-identity-rg`, where no CI identity has Contributor.

| Role | Scope | Needed by |
|---|---|---|
| Monitoring Contributor | `bastion-hub-rg`, `bastion-spoke-app-rg`, `bastion-test-rg` | Diagnostic settings (it includes `Microsoft.Insights/DiagnosticSettings/*` and `Microsoft.Resources/deployments/*`) |
| Website Contributor | the same 3 groups | App Service basic-auth fix |
| Bastion Diagnostics Destination (custom: `workspaces/read`, `workspaces/sharedKeys/action`) | `law-huginn` only | Use the workspace as a diagnostic settings destination |

Before the 2026-11-04 security review it also had Log Analytics Contributor on the three
groups and on `law-huginn`, because the Key Vault and NSG diagnostic built-ins list that
role in their `roleDefinitionIds`. Log Analytics Contributor includes
`Microsoft.OperationalInsights/*` (so on `law-huginn` it could delete or reconfigure
Huginn's workspace), `Microsoft.Compute/virtualMachines/extensions/*` and
`Microsoft.Storage/storageAccounts/listKeys/action`. It is now off by default on both:
`policy_identity_log_analytics_contributor` and `narrow_huginn_workspace_role` bring it
back if Azure refuses a remediation with the narrower roles (STATUS, Could not verify).

Sources for the narrower roles (Microsoft Learn, read from MicrosoftDocs on 2026-11-04):

- "Manage access to Log Analytics workspaces", example 3: `workspaces/read` and
  `workspaces/sharedKeys/action` on the workspace let a user "only enumerate the
  workspace and use it as a destination for diagnostic settings".
- "Azure built-in roles for Monitor": the permission lists of Monitoring Contributor and
  Log Analytics Contributor quoted above.

`sharedKeys/action` returns the workspace keys, which can still be used to send data into
the workspace. The identity can no longer read, change or delete Huginn's data or
settings, but it could add false records. See PREVENT-DETECT.

Bastion makes two writes outside its own groups, both on `law-huginn`: this role
assignment, and a `CanNotDelete` lock (`lock_huginn_workspace`, default on). No setting of
the workspace itself changes. The lock stops anyone deleting the workspace, including
Huginn's own Terraform, until it is removed (SETUP explains how).

### Why the apply identity can still attach the identity, and why that is dangerous

Attaching a user-assigned identity to any resource needs
`Microsoft.ManagedIdentity/userAssignedIdentities/*/assign/action` on the identity
(Microsoft Learn, "Managed identities for Azure resources frequently asked questions",
"Which Azure RBAC permissions are required to use a managed identity on a resource?").
A policy assignment with `identity.type = UserAssigned` is such a resource, so the apply
identity needs that right on `id-bastion-policy`. It gets it through the custom role
**Bastion Policy Identity Reference** (`userAssignedIdentities/read` and
`userAssignedIdentities/assign/action`), assigned on the identity resource only, not on its
group.

The same right is exactly what lets someone attach the identity to a container group, a
Function App or an Automation account and run code as it. That is the path the security
review found (PREVENT-DETECT, "Found in review"). The role assignment cannot be narrower,
so two more controls close the path:

- `denied_resource_types` blocks the compute types that can carry an identity in every
  Bastion group: container groups, Automation accounts, deployment scripts, Container Apps
  and jobs, App Service and Function Apps (`Microsoft.Web/sites`), Batch and Logic Apps,
  in addition to VMs and scale sets.
- a conftest rule fails any plan in which a resource other than a policy assignment
  references `id-bastion-policy`.

## Human access

No human has a standing Owner or Contributor on the workload groups. You remain Owner of
the subscription (you need it for the bootstrap), which is the main residual risk without
PIM (no Entra ID P1/P2 licence). See ADR 0008.
