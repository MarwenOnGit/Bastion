# Bastion baseline: policy controls

Source of truth: [policies/initiative.json](../policies/initiative.json) (what is in the
initiative), [policies/effects.json](../policies/effects.json) (current effect of each
control) and [policies/definitions/](../policies/definitions/) (the six custom
definitions). The table below is generated from those files.

**Scope of every assignment with real effects:** `bastion-hub-rg`, `bastion-spoke-app-rg`,
`bastion-test-rg`, `bastion-identity-rg` (ADR [0002](adr/0002-policy-scope-and-exclusions.md)). An optional
subscription assignment is audit-only and excludes every protected group.

**Status as of 2026-11-04:** written and statically tested. Not yet applied to Azure.
Nothing below is "enforced" until its policy test has passed against Azure. See
[STATUS.md](STATUS.md).

## Controls

21 controls, 31 policy references: 23 distinct built-in definitions and 6 custom ones.

- **MCSB** is the Microsoft cloud security benchmark control that Microsoft itself maps
  the built-in to, read from the `groupNames` of the MCSB v2 initiative
  (`e3ec7e09-768c-4b64-882c-fcada3772047`, v1.8.0). "none" means MCSB v2 does not include
  that definition; it does not mean the control is unrelated to the benchmark.
- **ALZ** is the Azure Landing Zones assignment that applies the same definition or idea
  (Azure-Landing-Zones-Library, commit `124b242`). See [ALZ-ALIGNMENT.md](ALZ-ALIGNMENT.md).

| Control | Definition | Version | Effect now | Target | MCSB | ALZ | Test | Fenrir |
|---|---|---|---|---|---|---|---|---|
| `storage_shared_key` | `8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54` Storage accounts should prevent shared key access | 2.1.0 | Audit | Deny | IM-1 | Enforce-GR-Storage | [test-storage-shared-key.sh](../tests/policy/test-storage-shared-key.sh) | P-12, D-01, D-02 |
| `storage_public_network` | `b2982f36-99f2-4db5-8eff-283140c09693` Storage accounts should disable public network access | 1.1.0 | Audit | Deny | NS-2 | Deny-Public-Endpoints | [test-storage-public-network.sh](../tests/policy/test-storage-public-network.sh) | D-01, D-02 |
| `keyvault_public_network` | `405c5871-3e91-4644-8a63-58e19d68ff5b` Azure Key Vault should disable public network access | 1.1.0 | Audit | Deny | NS-2 | Deny-Public-Endpoints | [test-keyvault-public-network.sh](../tests/policy/test-keyvault-public-network.sh) | none |
| `acr_admin_user` | `dc921057-6b28-4fbe-9b83-f7bec05db6c2` Container registries should have local admin account disabled. | 1.0.1 | Audit | Deny | IM-1 | Enforce-GR-ContReg | [test-acr-admin-user.sh](../tests/policy/test-acr-admin-user.sh) | P-13, D-03 |
| `appservice_basic_auth_audit` | `aede300b-d67f-480a-ae26-4b3dfb1a1fdc` App Service apps should have local authentication methods disabled for SCM site deployments | 1.1.0 | AuditIfNotExists | AuditIfNotExists | IM-1 | Enforce-GR-AppServices | compliance view | X-10, X-11 |
| | `871b205b-57cf-4e1e-a234-492616998bf7` App Service apps should have local authentication methods disabled for FTP deployments | 1.1.0 | | | | | | |
| | `5826c6cd-9302-4aee-bced-3b1698a08f29` Function apps should have local authentication methods disabled for SCM site deployments | 1.0.0 | | | | | | |
| | `3357bf2d-1d96-4829-9724-998ef6e7b1d2` Function apps should have local authentication methods disabled for FTP deployments | 1.0.0 | | | | | | |
| `appservice_basic_auth_fix` | `5e97b776-f380-4722-a9a3-e7f0be029e79` Configure App Service apps to disable local authentication for SCM sites | 1.1.0 | Disabled | DeployIfNotExists | none | Enforce-GR-AppServices | compliance view | X-10, X-11 |
| | `572e342c-c920-4ef5-be2e-1ed3c6a51dc5` Configure App Service apps to disable local authentication for FTP deployments | 1.1.0 | | | | | | |
| | `93059548-9cbe-4cdf-a2d1-63cc8db22550` Configure Function apps to disable local authentication for SCM sites | 1.0.0 | | | | | | |
| | `c7d3e3a0-533b-4ad2-9458-9b28f465ad36` Configure Function apps to disable local authentication for FTP deployments | 1.0.0 | | | | | | |
| `nic_no_public_ip` | custom `bastion-nic-no-public-ip` Bastion: network interfaces should not have public IPs | 1.0.0 | Audit | Deny | none | Deny-Public-IP-On-NIC | [test-nic-public-ip.sh](../tests/policy/test-nic-public-ip.sh) | none |
| `allowed_locations` | `e56962a6-4747-49cd-b67b-bf8b01975c4c` Allowed locations | 1.1.0 | Audit | Deny | none | none | [test-allowed-locations.sh](../tests/policy/test-allowed-locations.sh) | none |
| `required_tags` | custom `bastion-require-tag` Bastion: require a tag on resources | 1.0.0 | Audit | Deny | none | none | [test-required-tags.sh](../tests/policy/test-required-tags.sh) | none |
| | custom `bastion-require-tag` Bastion: require a tag on resources | 1.0.0 | | | | | | |
| | custom `bastion-require-tag` Bastion: require a tag on resources | 1.0.0 | | | | | | |
| `diagnostic_settings` | `6b359d8f-f88d-4052-aa7c-32015963ecc1` Enable logging by category group for Key vaults (microsoft.keyvault/vaults) to Log Analytics | 1.1.0 | AuditIfNotExists | DeployIfNotExists | LT-4 | Deploy-Diag-LogsCat (same idea) | compliance view | D-01, X-08, X-14 |
| | `baa4c6de-b7cf-4b12-b436-6e40ef44c8cb` Enable logging by category group for Network security groups (microsoft.network/networksecuritygroups) to Log Analytics | 1.0.0 | | | | | | |
| | `b4fe1a3b-0715-4c6c-a5ea-ffc33cf823cb` Configure diagnostic settings for Blob Services to Log Analytics workspace | 4.0.0 | | | | | | |
| `storage_secure_transfer` | `404c3081-a854-4457-ae30-26a93ef643f9` Secure transfer to storage accounts should be enabled | 2.0.0 | Audit | Deny | DP-3 | Deny-Storage-http | [test-storage-secure-transfer.sh](../tests/policy/test-storage-secure-transfer.sh) | D-01 |
| `storage_min_tls` | `fe83a0eb-a853-422d-aac2-1bffd182c5d0` Storage accounts should have the specified minimum TLS version | 1.0.0 | Audit | Deny | DP-3 | none | [test-storage-min-tls.sh](../tests/policy/test-storage-min-tls.sh) | none |
| `storage_blob_public_access` | `4fa4b6c0-31ca-4c0d-b10d-24b96f62a751` Storage account public access should be disallowed | 3.1.1 | Audit | Deny | NS-2 | none | [test-storage-blob-public-access.sh](../tests/policy/test-storage-blob-public-access.sh) | D-01 |
| `keyvault_rbac` | `12d4fa5e-1f9f-4c21-97a9-b99b3c6611b5` Azure Key Vault should use RBAC permission model | 1.0.1 | Audit | Deny | PA-7 | Enforce-GR-KeyVault | [test-keyvault-rbac.sh](../tests/policy/test-keyvault-rbac.sh) | E-27 |
| `keyvault_purge_protection` | `0b60c0b2-2dc2-4e1c-b5c9-abbed971de53` Key vaults should have deletion protection enabled | 2.1.0 | Audit | Deny | DP-8 | Enforce-GR-KeyVault | [test-keyvault-purge-protection.sh](../tests/policy/test-keyvault-purge-protection.sh) | none |
| `subnet_private` | `7bca8353-aa3b-429b-904a-9229c4385837` Subnets should be private | 1.1.0 | Audit | Deny | none | Enforce-Subnet-Private | [test-subnet-private.sh](../tests/policy/test-subnet-private.sh) | none |
| `subnet_nsg` | custom `bastion-subnet-requires-nsg` Bastion: subnets must have a network security group | 1.0.0 | Audit | Deny | NS-1 (built-in twin) | Deny-Subnet-Without-Nsg | [test-subnet-nsg.sh](../tests/policy/test-subnet-nsg.sh) | none |
| `mgmt_ports_internet` | custom `bastion-deny-mgmt-ports-from-internet` Bastion: management ports must not be open to the internet | 1.0.0 | Audit | Deny | none | Deny-MgmtPorts-Internet | [test-mgmt-ports-internet.sh](../tests/policy/test-mgmt-ports-internet.sh) | none |
| `denied_resource_types` | `6c112d4e-5bc7-47ae-a041-ea2d9dccd749` Not allowed resource types | 2.0.0 | Audit | Deny | none | Deny-Classic-Resources / Enforce-ALZ-Sandbox (same built-in) | [test-denied-resource-types.sh](../tests/policy/test-denied-resource-types.sh) | X-08 |
| `protect_diagnostic_settings` | custom `bastion-deny-delete-diagnostic-settings` Bastion: block deletion of diagnostic settings | 1.0.0 | Disabled | DenyAction | none | DenyAction-DiagnosticLogs | manual check (below) | none |
| `delete_protection` | custom `bastion-deny-delete-protected` Bastion: block deletion of resources tagged bastion-protected | 1.0.0 | Disabled | DenyAction | none | DenyAction-DeleteResources (pattern) | [test-delete-protection.sh](../tests/policy/test-delete-protection.sh) | none |

The diagnostic-settings control sends to `law-huginn`
(`/subscriptions/42146134-9464-4c2d-86b0-afe414704284/resourceGroups/huginn-sentinel-rg/providers/Microsoft.OperationalInsights/workspaces/law-huginn`).
Its remediation identity and roles are in ADR [0006](adr/0006-ci-identities-and-least-privilege.md).

`denied_resource_types` blocks these types in the Bastion groups (variable
`denied_resource_types` in `infra/governance`): Azure Firewall and firewall policies, the
Azure Bastion service, VPN and virtual network gateways, ExpressRoute circuits and
gateways, DDoS protection plans, Application Gateway, NAT gateway, Virtual WAN hubs,
public IPs and prefixes, VMs and scale sets, and every other compute type that can carry
a managed identity: container groups, Automation accounts, deployment scripts, Container
Apps and jobs, App Service and Function Apps (`Microsoft.Web/sites`), Batch accounts and
Logic Apps. Because `Microsoft.Web/sites` is denied, the App Service basic-auth controls
have nothing to evaluate today; they stay as a second layer in case the deny is relaxed.

## The custom definitions and why each exists

| File | Why not a built-in |
|---|---|
| `bastion-nic-no-public-ip.json` | Built-in `83a86a26...` has its effect fixed to Deny, so it cannot start in Audit. Rule unchanged |
| `bastion-require-tag.json` | Built-in `871b6d14...` has its effect fixed to Deny. Rule unchanged |
| `bastion-subnet-requires-nsg.json` | The built-in (`e71308d3...`) only supports AuditIfNotExists. Copied from ALZ `Deny-Subnet-Without-Nsg` v2.1.0 (MIT), default effect changed to Audit |
| `bastion-deny-mgmt-ports-from-internet.json` | No built-in denies the NSG rule itself. Copied from ALZ `Deny-MgmtPorts-From-Internet` v2.2.0 (MIT), default effect changed to Audit |
| `bastion-deny-delete-diagnostic-settings.json` | No built-in DenyAction for diagnostic settings. Copied from ALZ `DenyAction-DiagnosticLogs` with an effect parameter added |
| `bastion-deny-delete-protected.json` | Pattern of ALZ `DenyAction-DeleteResources`, keyed on the `bastion-protected` tag |

Each file names its source and version in `metadata.source`. When the upstream definition
changes, compare and update the copy.

## Corrections to the original plan

| Plan said | What is true | What Bastion does |
|---|---|---|
| "No public IPs on NICs: Deny" with Audit first | The built-in's effect is fixed to Deny | Custom copy with an effect parameter. `denied_resource_types` also blocks public IPs themselves |
| "Required tags: Deny or Modify" with Audit first | "Require a tag" is fixed Deny; "Add a tag" and "Inherit a tag" are fixed Modify | Custom copy of "Require a tag" with an effect parameter. No Modify control |
| "App Service basic auth: Deny or Modify" | No built-in offers Deny or Modify. The built-ins are AuditIfNotExists (report) and DeployIfNotExists (fix) | Both, as two controls. Not preventive: there is a window between creation and remediation |
| "Storage disable shared key: Deny" | There are three built-ins with that name; the general one is `8c6a50c6...` v2.1.0 | Uses `8c6a50c6...`, the one ALZ's storage guardrails use |
| "Diagnostic settings: DeployIfNotExists" with Audit first | These built-ins allow AuditIfNotExists, so they can start in an audit mode | AuditIfNotExists first |
| "Azure Policy cannot block actions" | Policy has a `denyAction` effect, but the only supported action is `delete` | Two DenyAction controls (diagnostic settings, tagged resources). Run Command and exec still need RBAC (ADR [0008](adr/0008-rbac-for-actions-policy-cannot-block.md)) |

## What Azure Policy can and cannot do here

- **Deny** evaluates the request body of a create or update (PUT or PATCH). It is what
  every `test-*.sh` exercises.
- **DenyAction** blocks `delete`, and only `delete`. Some types are exempt to prevent
  lockouts: policy assignments, deny assignments, deployment stacks, subscriptions and
  locks. A delete of a parent still removes its children and extensions (deleting a Key
  Vault removes its diagnostic setting), and only `cascadeBehaviors: deny` blocks a
  resource group delete.
- **Nothing in Policy** evaluates POST actions such as VM Run Command (X-08), container
  exec (X-14), Logic App `listCallbackUrl` (X-13), `listKeys` (P-12) or `listCredentials`
  (P-13). Those are limited with RBAC: see ADR [0008](adr/0008-rbac-for-actions-policy-cannot-block.md).

Source: Microsoft Learn, "Azure Policy definitions denyAction effect"
(`articles/governance/policy/concepts/effect-deny-action.md` in MicrosoftDocs/azure-docs,
read 2026-11-04).

## How each control is tested

- **Deny controls:** one script per control in `tests/policy/`. It runs as
  `bastion-policy-tester`, makes one direct ARM PUT of a non-compliant resource in
  `bastion-test-rg` (every other property compliant, so only the control under test can
  deny) and passes only if Azure returns `RequestDisallowedByPolicy` naming the
  `bastion-baseline` assignment and the expected reference ID. A test runs only when its
  control is enforced in `policies/effects.json`.
- **delete_protection (DenyAction):** `test-delete-protection.sh` keeps a permanent, free
  canary (`id-bastion-canary`, tagged `bastion-protected=true`) in `bastion-test-rg`, then
  tries to delete it and passes only on a 403 that names `bastion-baseline`.
- **protect_diagnostic_settings (DenyAction), manual check:** the tester identity cannot
  create a diagnostic setting (that needs rights on `law-huginn`), so this one is checked by
  hand after the diagnostic-settings control has deployed a setting:

  ```bash
  kv=$(az keyvault list -g bastion-spoke-app-rg --query '[0].id' -o tsv)
  ```

  ```bash
  az monitor diagnostic-settings delete --resource "$kv" --name bastion-to-law-huginn
  ```

  Expected: a 403 that names `bastion-baseline`.
- **AuditIfNotExists and DeployIfNotExists controls:** checked in the compliance report,
  which the nightly `drift` workflow publishes, or locally:

  ```bash
  tests/policy/compliance-report.sh
  ```

## How the IDs were verified

On 2026-11-03 and 2026-11-04, from the build session (learn.microsoft.com was not
reachable from it), against the source of the published definitions:

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/Azure/azure-policy
```

```bash
cd azure-policy && git sparse-checkout set built-in-policies
```

For each built-in in `policies/initiative.json` the check compared the GUID, display name,
version, allowed effects and parameter names (commit `f096d8d`, 2026-10-28). All 23
matched. MCSB groups come from `policySetDefinitions/Security Center/MCSBv2.json` in the
same commit. To re-check one against the live service:

```bash
az policy definition show --name 8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54 --query "{name:displayName, version:version, effects:parameters.effect.allowedValues}"
```
