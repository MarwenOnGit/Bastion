# ADR 0006: CI identities and least privilege

Date: 2026-11-03. Status: accepted.

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
| Contributor | `bastion-hub-rg`, `bastion-spoke-app-rg` | Network and workload resources; assign the policy identity |
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
| Policy identity `id-bastion-policy` and its roles | `roleAssignments/write` |
| Management groups | the creator becomes Owner of each group |
| Resource provider registration | `register/action` at subscription scope |

### Policy identity: id-bastion-policy

A user-assigned identity used by every DeployIfNotExists member. Roles, taken from the
`roleDefinitionIds` of the built-ins:

| Role | Scope | Needed by |
|---|---|---|
| Log Analytics Contributor | the 3 Bastion groups and `law-huginn` | Diagnostic settings (Key Vault, NSG, blob) |
| Monitoring Contributor | the 3 Bastion groups | Blob diagnostic settings |
| Website Contributor | the 3 Bastion groups | App Service basic-auth fix |

The built-in diagnostic-settings policies say that when the workspace is outside the
assignment scope, Log Analytics Contributor (or similar) must be granted on it by hand.
That is the one role assignment Bastion makes in `huginn-sentinel-rg`. No resource there
changes. Set `grant_policy_identity_on_huginn_workspace = false` to skip it; the
diagnostic-settings control then reports but cannot deploy.

## Human access

No human has a standing Owner or Contributor on the workload groups. You remain Owner of
the subscription (you need it for the bootstrap), which is the main residual risk without
PIM (no Entra ID P1/P2 licence). See ADR 0008.
