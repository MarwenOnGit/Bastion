# Bastion baseline: policy controls

Source of truth: [policies/initiative.json](../policies/initiative.json) (what is in the
initiative), [policies/effects.json](../policies/effects.json) (current effect of each
control) and [policies/definitions/](../policies/definitions/) (the two custom copies).

**Scope of every assignment with real effects:** `bastion-hub-rg`, `bastion-spoke-app-rg`,
`bastion-test-rg` (ADR [0002](adr/0002-policy-scope-and-exclusions.md)). An optional
subscription assignment is audit-only and excludes every protected group.

**Status as of 2026-11-03:** written and statically tested. Not yet applied to Azure.
Nothing below is "enforced" until a policy test has passed against Azure. See
[STATUS.md](STATUS.md).

## Controls

| Control | Definition (built-in GUID or custom name) | Version | Effect now | Target | Policy test | Fenrir |
|---|---|---|---|---|---|---|
| `storage_shared_key` | `8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54` Storage accounts should prevent shared key access | 2.1.0 | Audit | Deny | [test-storage-shared-key.sh](../tests/policy/test-storage-shared-key.sh) | P-12, D-01, D-02 |
| `storage_public_network` | `b2982f36-99f2-4db5-8eff-283140c09693` Storage accounts should disable public network access | 1.1.0 | Audit | Deny | [test-storage-public-network.sh](../tests/policy/test-storage-public-network.sh) | D-01, D-02 |
| `keyvault_public_network` | `405c5871-3e91-4644-8a63-58e19d68ff5b` Azure Key Vault should disable public network access | 1.1.0 | Audit | Deny | [test-keyvault-public-network.sh](../tests/policy/test-keyvault-public-network.sh) | none |
| `acr_admin_user` | `dc921057-6b28-4fbe-9b83-f7bec05db6c2` Container registries should have local admin account disabled. | 1.0.1 | Audit | Deny | [test-acr-admin-user.sh](../tests/policy/test-acr-admin-user.sh) | P-13, D-03 |
| `appservice_basic_auth_audit` | `aede300b-d67f-480a-ae26-4b3dfb1a1fdc` App Service apps: SCM local auth disabled | 1.1.0 | AuditIfNotExists | AuditIfNotExists | compliance view | X-10, X-11 |
| | `871b205b-57cf-4e1e-a234-492616998bf7` App Service apps: FTP local auth disabled | 1.1.0 | | | | |
| | `5826c6cd-9302-4aee-bced-3b1698a08f29` Function apps: SCM local auth disabled | 1.0.0 | | | | |
| | `3357bf2d-1d96-4829-9724-998ef6e7b1d2` Function apps: FTP local auth disabled | 1.0.0 | | | | |
| `appservice_basic_auth_fix` | `5e97b776-f380-4722-a9a3-e7f0be029e79` Configure App Service apps to disable local auth for SCM | 1.1.0 | Disabled | DeployIfNotExists | remediation check (see below) | X-10, X-11 |
| | `572e342c-c920-4ef5-be2e-1ed3c6a51dc5` Configure App Service apps to disable local auth for FTP | 1.1.0 | | | | |
| | `93059548-9cbe-4cdf-a2d1-63cc8db22550` Configure Function apps to disable local auth for SCM | 1.0.0 | | | | |
| | `c7d3e3a0-533b-4ad2-9458-9b28f465ad36` Configure Function apps to disable local auth for FTP | 1.0.0 | | | | |
| `nic_no_public_ip` | custom `bastion-nic-no-public-ip` (copy of `83a86a26-fd1f-447c-b59d-e51f44264114`) | 1.0.0 | Audit | Deny | [test-nic-public-ip.sh](../tests/policy/test-nic-public-ip.sh) | none |
| `allowed_locations` | `e56962a6-4747-49cd-b67b-bf8b01975c4c` Allowed locations | 1.1.0 | Audit | Deny | [test-allowed-locations.sh](../tests/policy/test-allowed-locations.sh) | none |
| `required_tags` | custom `bastion-require-tag` (copy of `871b6d14-10aa-478d-b590-94f262ecfa99`), three times: `owner`, `env`, `project` | 1.0.0 | Audit | Deny | [test-required-tags.sh](../tests/policy/test-required-tags.sh) | none |
| `diagnostic_settings` | `6b359d8f-f88d-4052-aa7c-32015963ecc1` Key Vault logs (category group allLogs) to Log Analytics | 1.1.0 | AuditIfNotExists | DeployIfNotExists | compliance view | supports D-01 detection |
| | `baa4c6de-b7cf-4b12-b436-6e40ef44c8cb` NSG logs (allLogs) to Log Analytics | 1.0.0 | | | | |
| | `b4fe1a3b-0715-4c6c-a5ea-ffc33cf823cb` Blob service diagnostic settings to Log Analytics | 4.0.0 | | | | |

The diagnostic-settings control sends to `law-huginn`
(`/subscriptions/42146134-9464-4c2d-86b0-afe414704284/resourceGroups/huginn-sentinel-rg/providers/Microsoft.OperationalInsights/workspaces/law-huginn`).
Its remediation identity and roles are in ADR [0006](adr/0006-ci-identities-and-least-privilege.md).

## Corrections to the original plan

| Plan said | What is true | What Bastion does |
|---|---|---|
| "No public IPs on NICs: Deny" with Audit first | The built-in's effect is fixed to Deny | Custom copy with an effect parameter |
| "Required tags: Deny or Modify" with Audit first | "Require a tag" is fixed Deny; "Add a tag" and "Inherit a tag" are fixed Modify | Custom copy of "Require a tag" with an effect parameter. No Modify control. |
| "App Service basic auth: Deny or Modify" | No built-in offers Deny or Modify. The built-ins are AuditIfNotExists (report) and DeployIfNotExists (fix) | Both, as two controls. Not a preventive control: there is a window between creation and remediation |
| "Storage disable shared key: Deny" | There are three built-ins with that name; the general one is `8c6a50c6...` v2.1.0 | Uses `8c6a50c6...` |
| "Diagnostic settings: DeployIfNotExists" with Audit first | These built-ins allow AuditIfNotExists, so they can start in an audit mode | AuditIfNotExists first |

## What Azure Policy cannot do here

Azure Policy evaluates resource properties on create and update. It does **not** evaluate
actions such as VM Run Command (X-08), container exec (X-14), Logic App `listCallbackUrl`
(X-13), `listKeys` (P-12) or `listCredentials` (P-13). Those are limited with RBAC, not
Policy: see ADR [0008](adr/0008-rbac-for-actions-policy-cannot-block.md).

## How each control is tested

- **Deny controls:** one script per control in `tests/policy/`. It runs as
  `bastion-policy-tester`, makes one direct ARM PUT of a non-compliant resource in
  `bastion-test-rg` and passes only if Azure returns `RequestDisallowedByPolicy` naming the
  `bastion-baseline` assignment and the expected reference ID. A test runs only when its
  control is Deny in `policies/effects.json`.
- **AuditIfNotExists and DeployIfNotExists controls:** no Deny test is possible. They are
  checked in the compliance view:

  ```bash
  az policy state summarize --resource-group bastion-spoke-app-rg --policy-assignment bastion-baseline
  ```

  For the diagnostic-settings control after it moves to DeployIfNotExists, check that the
  Key Vault in the spoke has a diagnostic setting named `bastion-to-law-huginn`:

  ```bash
  az monitor diagnostic-settings list --resource "$(az keyvault list -g bastion-spoke-app-rg --query '[0].id' -o tsv)"
  ```

## How the IDs were verified

On 2026-11-03, from the build session (Microsoft Learn was not reachable from it), against
the source of the published definitions:

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/Azure/azure-policy
cd azure-policy && git sparse-checkout set built-in-policies/policyDefinitions
```

For each built-in in `policies/initiative.json` the check compared the GUID, display name,
version, allowed effects and parameter names. All 16 matched. To re-check against the live
service:

```bash
az policy definition show --name 8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54 --query "{name:displayName, version:version, effects:parameters.effect.allowedValues}"
```
