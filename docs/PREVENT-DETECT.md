# Prevent and detect: Fenrir against Bastion and Huggin

**Bastion prevents, Huggin detects.** For every Fenrir operation in Huggin's inventory
([FENRIR-OPERATIONS.md](https://github.com/MarwenOnGit/Huggin/blob/main/docs/FENRIR-OPERATIONS.md),
Fenrir commit `5959162`), this table says what Bastion does to prevent it, which Huggin
rule detects it ([FENRIR-MAPPING.md](https://github.com/MarwenOnGit/Huggin/blob/main/docs/FENRIR-MAPPING.md)),
and what is left.

Status words:

- **Prevents (designed):** a Bastion control exists in code but has not yet been proven
  by a policy test against Azure. As of 2026-11-03 every Bastion control is in this state,
  because nothing has been applied yet (see [STATUS.md](STATUS.md)).
- **Limits:** Bastion does not stop the operation but reduces what it can reach or what
  its result is worth.
- **No:** Bastion does nothing about it.
- Huggin "validated" means a benign replay passed, as recorded in Huggin's STATUS on
  2026-11-03.

Most of the important controls work by **RBAC, not Policy**. Azure Policy cannot block an
action such as Run Command, exec, `listKeys` or `listCredentials`: its Deny effect only
judges create and update requests, and its DenyAction effect only supports `delete` (ADR
[0008](adr/0008-rbac-for-actions-policy-cannot-block.md)). Policy can make the result of some
actions useless, and it can make the *target* impossible to create.

Scope: Bastion's controls apply to the Bastion resource groups. In the Fenrir lab
(`fenrir-lab-prod-rg`) nothing is prevented, by design.

## Sign-in

| Op | What Fenrir does | Bastion | Huggin | Gap |
|---|---|---|---|---|
| A-01 | MSAL public client with the Azure CLI client ID | No | Context for other rules | Cannot be told apart from a real `az login` by client ID |
| A-02 | Device code sign-in | No. Blocking device code flow needs Conditional Access (Entra ID P1) | `devicecode-azure-mgmt-signin` (new, not validated) | No P1 in this tenant. Sign-in logs cannot be exported to Log Analytics without P1/P2, so this rule has no data here |
| A-03 | Interactive sign-in | No | none | Same licence gap |
| A-04 | ROPC sign-in | No (Conditional Access, P1) | `devicecode-azure-mgmt-signin` ROPC branch (not validated) | Same licence gap |
| A-05 | Silent token for ARM from the refresh token | No | context only | Same licence gap |

## enumerate

| Op | What Fenrir does | Bastion | Huggin | Gap |
|---|---|---|---|---|
| E-01 to E-07 | Graph reads: `/me`, domains, directory roles, PIM, groups, owned objects, devices | No | `graph-directory-recon` (new, not validated) | Needs `MicrosoftGraphActivityLogs`, which needs Entra ID P1/P2. Blind spot here |
| E-08 to E-13 | ARM reads: management groups, subscriptions, groups, resources, role assignments | No. Reads by an authorised principal are allowed | none possible | Blind spot: `AzureActivity` does not record GETs |
| E-14 to E-27 | Reads in "interesting" groups (where the caller holds Owner, Contributor, VM Contributor, Website Contributor and similar roles) | **Limits (designed):** no human or workload has a standing role from Fenrir's list on the Bastion groups; Bastion VM Operator is not on it (ADR 0008). Fenrir does not treat the Bastion groups as interesting | none possible | Blind spot. You, as subscription Owner, still see everything |

## exploit

| Op | What Fenrir does | Bastion | Huggin | Gap |
|---|---|---|---|---|
| X-01 to X-04 | Discovery reads (subscriptions, groups, `GET /me`, role assignments) | No | none possible | Blind spot |
| X-05 | Same reads as E-14 to E-27 | Limits (designed), as above | none possible | Blind spot |
| X-06 | Graph `GET /servicePrincipals` for the whole tenant | No | `graph-directory-recon` (not validated) | Needs P1/P2 for Graph activity logs |
| X-07 | RBAC permission preflight | No | none possible | Blind spot |
| X-08 | VM Run Command | **Prevents (designed):** `denied_resource_types` stops any VM from being created in the Bastion groups, so there is no target. If a VM is ever allowed, RBAC takes over: Bastion VM Operator excludes `runCommand`, `runCommands/write` and `extensions/write`, and no one has a standing Contributor. Policy cannot block the action itself | `vm-runcommand-by-user` **validated** 2026-11-03; `fenrir-chain` validated | A principal with Contributor (including you, and the apply identity during an approved run) can still do it |
| X-09 | Run Command status polling | Follows X-08 | none | Blind spot (read) |
| X-10 | List App Service publishing credentials | **Limits (designed):** `appservice_basic_auth_fix` turns SCM and FTP basic auth off, so the credentials stop working. Bastion VM Operator excludes `config/list`. Policy cannot block the list action | `appservice-publish-creds` (not validated) | The list call still succeeds for Contributor. There is a window between app creation and remediation. The fix control starts Disabled (ADR 0003) |
| X-11 | Kudu `/api/command` with Basic auth | **Prevents (designed)** once basic auth is off for SCM (verify in Azure) | `appservice-publish-creds` optional join, needs App Service diagnostic settings | Bastion's diagnostic-settings control does not cover App Service yet (roadmap) |
| X-12 | List Logic App triggers | No | none possible | Blind spot (read) |
| X-13 | Logic App `listCallbackUrl` | Limits: no standing Logic App Contributor or Contributor. Policy cannot block it | `logicapp-callback-listed` **validated** 2026-11-03 | Contributor can still do it |
| X-14 | Container Instances exec | **Prevents (designed), by RBAC:** Bastion VM Operator excludes `containers/exec/action`; no standing Contributor. Policy cannot block it | `aci-exec` (not validated) | Contributor can still do it; session content is never logged |
| X-15 to X-18 | Automation Account reads: runbooks, **runbook source**, variables, credential names | Limits: no Automation Accounts in Bastion; no standing Automation roles | none possible | Blind spot. Reading runbook source leaves no record anywhere |
| X-19 to X-21 | Reads as the stolen managed identity from the operator's IP | Limits: Bastion's only managed identity (`id-bastion-policy`) has roles on the Bastion groups and `law-huginn` only | none possible | Blind spot |

## post-exploit

| Op | What Fenrir does | Bastion | Huggin | Gap |
|---|---|---|---|---|
| P-01 to P-11 | Reads as the managed identity (subscriptions, groups, resources, permissions, storage accounts, registries) | Limits: least-privilege managed identity, as X-19 to X-21 | none possible | Blind spot |
| P-12 | Storage `listKeys` | **Prevents the use (designed):** `storage_shared_key` (Deny target) means the keys cannot authenticate; every Bastion account sets `shared_access_key_enabled = false` (conftest and pytest check it). Policy cannot block `listKeys` itself | `storage-keys-listed` **partly validated** (branch C) 2026-11-03; `mi-control-plane-new-ip` (new) | `listKeys` still returns keys to a principal with the right role; they are just useless. Branch A needs the purple-team run |
| P-13 | ACR `listCredentials` | **Prevents the use (designed):** `acr_admin_user` (Deny target); conftest rejects `admin_enabled = true` | `acr-admin-creds-listed` (new, not validated) | Same as P-12 |
| D-01 | Blob listing and download (account key or OAuth) | **Prevents (designed):** shared key off (no key auth), `storage_public_network` (no path from the operator's machine, even with an OAuth token), `storage_blob_public_access` (no anonymous containers), `storage_secure_transfer` and `storage_min_tls` (no clear text, no old TLS) | `StorageBlobLogs` reach `law-huginn` through `diagnostic_settings` once it is DeployIfNotExists; no Huggin rule yet | A principal inside the VNet with a data role can still read. With shared keys off, account and service SAS stop working, but a user delegation SAS (signed with Entra ID) still works for anyone with the role to create one |
| D-02 | File share listing and download | Same as D-01 | `StorageFileLogs`: not in Bastion's diagnostic settings (blob only) | No file log collection |
| D-03 | ACR token exchange, catalog, image pull | Prevents admin-credential use (designed); no registry exists in Bastion | out of scope in Huggin | No registry logs |

## Defence evasion: deleting the logs

Fenrir does not do this, but the next step for an attacker who has Contributor is often to
delete diagnostic settings, so the actions that follow leave no trace in Sentinel.
`protect_diagnostic_settings` (DenyAction, from the Azure Landing Zones
`DenyAction-DiagnosticLogs` definition) refuses any delete of a diagnostic setting in the
Bastion groups. The subscription Activity log export belongs to Huggin and is outside
Bastion's scope.

## Every prevented attempt is also a detection

Huggin exports the subscription Activity log, including the **Policy** category, to
`law-huginn`. When `bastion-baseline` denies a request, Azure writes a Policy event with
operation `Microsoft.Authorization/policies/deny/action`, and the assignment name in
`properties.policies` (Activity log schema, "Policy category"). So a blocked attempt is not
silent. This query lists denials by Bastion, with who tried and what (verify field names
in `law-huginn`; the `Properties_d` layout can differ between workspaces):

```kusto
AzureActivity
| where TimeGenerated > ago(7d)
| where CategoryValue == "Policy"
| where OperationNameValue =~ "Microsoft.Authorization/policies/deny/action"
| extend policies = parse_json(tostring(Properties_d.policies))
| mv-expand policy = policies
| where tostring(policy.policyAssignmentName) == "bastion-baseline"
| project TimeGenerated, Caller, CallerIpAddress, ResourceGroup, _ResourceId,
          Reference = tostring(policy.policyDefinitionReferenceId)
| order by TimeGenerated desc
```

The policy tests produce these events every night on purpose, as `bastion-policy-tester`.
A Huggin rule built on this query should exclude that caller, and alert on denials by
anyone else, especially a managed identity (Fenrir's post-exploit caller). That rule
belongs in Huggin, not here. It now exists there as a draft,
[`bastion-policy-denial`](https://github.com/MarwenOnGit/Huggin/tree/main/detections/beyond-fenrir/bastion-policy-denial),
and excludes the tester through Huggin's trusted-automation watchlist
([SETUP.md](SETUP.md), step 2). It cannot be validated until a control is in Deny.

## Summary

| | Count |
|---|---|
| Fenrir operations in the inventory | 66 (plus D-01 to D-03) |
| Prevented or made useless by a Bastion control (designed, not yet proven) | X-08 (no VM can exist), X-11, X-14, P-12, P-13, D-01, D-02, D-03 |
| Limited by least privilege | E-14 to E-27, X-05, X-10, X-13, X-15 to X-21, P-01 to P-11 |
| Detected by a validated Huggin rule | X-08, X-13, P-12 (partly) |
| Neither prevented nor detected | A-01 to A-05 (no P1 licence), E-01 to E-13, X-01 to X-04, X-06, X-07, X-09, X-12 |

The largest gap is identity: without Entra ID P1/P2 there is no Conditional Access, no PIM,
and no sign-in or Graph activity logs in Log Analytics. Bastion cannot fix that in code.
