# Setup: the steps only you can do

Everything that changes Azure is run by you: the bootstrap on your laptop, then the
`apply` workflow that you approve. Nothing here needs a secret.

## 0. The `main` branch

The repository was empty when Bastion was built, and the build session was not allowed
to push to `main`. Because `bastion-dev` was pushed first, GitHub made it the default
branch. Create `main` from the first commit (a README only) and make it the default:

```bash
git fetch origin bastion-dev
git push origin "$(git rev-list --max-parents=0 origin/bastion-dev):refs/heads/main"
```

Then in GitHub: Settings > General > Default branch > `main`. Then open (or review) the
pull request from `bastion-dev` to `main`.

## 1. Prerequisites on your laptop

- Terraform 1.9 or later, Azure CLI, jq.
- Signed in as the Global Administrator who is Owner of the subscription:

```bash
az login --tenant 972afa9f-85f2-4581-81c4-a126c475a06d
```

```bash
az account set --subscription 42146134-9464-4c2d-86b0-afe414704284
```

- Huggin's `sentinel` stack applied, so `law-huginn` exists in `huginn-sentinel-rg`.
  Bastion builds the workspace ID from names and does not check it: the role assignment
  in step 2 fails if the workspace is missing, and the diagnostic-settings controls
  point at nothing. If you ever run `make destroy` in Huggin, Bastion's logs stop
  arriving until the workspace is back.
- Creating management groups under the Tenant Root Group: if the hierarchy settings
  require write access on the root, elevate access first (Entra ID > Properties > Access
  management for Azure resources > Yes), and turn it off again after step 2.

## 2. Bootstrap (once)

Read the plan before you apply it. It creates 4 resource groups, the state account, 3 app
registrations with federated credentials, role assignments, 1 custom role, 1 managed
identity, 4 management groups, a diagnostic setting on the state account, and one role
assignment on `law-huginn`.

```bash
terraform -chdir=infra/bootstrap init
```

```bash
terraform -chdir=infra/bootstrap plan -out=bootstrap.tfplan
```

```bash
terraform -chdir=infra/bootstrap apply bootstrap.tfplan
```

Then record the provider checksums for every stack and commit the lock files. HashiCorp
recommends committing `.terraform.lock.hcl`; the build session could not create them
because the Terraform registry was blocked there. Include the runner's platform and yours:

```bash
for s in bootstrap governance network workload; do terraform -chdir=infra/$s providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=windows_amd64; done
```

The state stays in `infra/bootstrap/terraform.tfstate` (git-ignored). Back it up
somewhere private. It holds no secrets.

Commit the generated `infra/shared/bootstrap.json` (non-secret IDs) on `bastion-dev`.

### Register Bastion's pipelines with Huggin

Two things Bastion's CI does nightly look like Fenrir to Huggin's rules:

- **`listKeys` on every plan.** The azurerm provider (4.81) calls
  `Microsoft.Storage/storageAccounts/listKeys/action` each time it reads a storage
  account, even with shared keys off, and ignores a 403. The Reader identity
  `bastion-github-plan` (`plan.yml`, `drift.yml`) and `bastion-github-apply` therefore
  write `listKeys` rows (failed or not) for the state account and the workload account.
  Huggin's `storage-keys-listed` would raise them as new caller and account pairs.
- **Policy denials on purpose.** `bastion-policy-tester` triggers denials in
  `bastion-test-rg` every night. Huggin's `bastion-policy-denial` rule must not alert on them.

In the Huggin repository, set `bastion_identities` in
`infra/sentinel/huginn.auto.tfvars.json` and apply Huggin's `sentinel` stack. Huggin then
generates watchlist rows for exactly these operations: `listKeys` for plan and apply on
`bastion-*` groups, policy denials for the tester on `bastion-test-rg`. This prints the
value from `infra/shared/bootstrap.json`:

```bash
jq --arg exp "$(date -u -d '+180 days' +%Y-%m-%d)" '{bastion_identities: {
  plan_object_id: .identities.plan.object_id,
  apply_object_id: .identities.apply.object_id,
  policy_tester_object_id: .identities.policy_tester.object_id,
  expires_on: $exp}}' infra/shared/bootstrap.json
```

The rows match on principal, scope and operation together (Huggin's
[LEGIT-BASELINE.md](https://github.com/MarwenOnGit/Huggin/blob/main/docs/LEGIT-BASELINE.md),
principle 2), so a `listKeys` by the same identity outside the `bastion-*` groups still
alerts. Renew `expires_on` before it passes.

## 3. GitHub environments

Settings > Environments:

| Environment | Required reviewers | Deployment branches |
|---|---|---|
| `bastion-apply` | you (`MarwenOnGit`) | Selected branches: `main` only |
| `bastion-policy-tests` | none (it runs nightly) | Selected branches: `main` only |

## 4. GitHub repository variables

Settings > Secrets and variables > Actions > **Variables** (not secrets; none of these is
secret). The values come from the bootstrap output:

```bash
terraform -chdir=infra/bootstrap output -json github_variables
```

Set them all with the GitHub CLI:

```bash
terraform -chdir=infra/bootstrap output -json github_variables | jq -r 'to_entries[] | "\(.key) \(.value)"' | while read -r k v; do gh variable set "$k" --repo MarwenOnGit/Bastion --body "$v"; done
```

Then add the two that are not in the output:

```bash
gh variable set BUDGET_ALERT_EMAIL --repo MarwenOnGit/Bastion --body "<your alert address>"
```

```bash
gh variable set BASTION_LOCATION --repo MarwenOnGit/Bastion --body "francecentral"
```

| Variable | Used by |
|---|---|
| `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | all Azure jobs |
| `AZURE_PLAN_CLIENT_ID` | plan, drift |
| `AZURE_APPLY_CLIENT_ID` | apply |
| `AZURE_TESTER_CLIENT_ID` | policy-tests |
| `TFSTATE_STORAGE_ACCOUNT` | plan, apply, drift |
| `BUDGET_ALERT_EMAIL` | governance stack (budget) |
| `BASTION_LOCATION` | policy-tests |

The budget amount defaults to $20 a month. To change it, edit `budget_amount` in
`infra/governance/variables.tf` in a pull request.

## 5. First plan

Push anything to `bastion-dev` (or run Actions > plan > Run workflow). The plan job logs
in as `bastion-github-plan` and posts each stack's plan to the job summary. The workload
plan fails until the network stack exists (it reads the subnet and DNS zones).

## 6. Apply, one stack at a time (after merging to main)

Actions > apply > Run workflow on `main`, then approve the `bastion-apply` deployment:

1. `governance` (policy in Audit mode, budget, free CSPM)
2. `network`
3. `workload` (optional, about $15 a month while it exists; destroy after the demo)

## 7. Audit results (Phase 6 input)

The nightly `drift` workflow publishes a compliance report (per control, with every
non-compliant resource) in its job summary. To get one now, run Actions > drift > Run
workflow, or locally (the `--scan` flag starts a fresh evaluation first, which can take
several minutes):

```bash
tests/policy/compliance-report.sh --scan
```

Paste the report back to start Phase 6.

## 8. Policy tests

Actions > policy-tests > Run workflow on `main`. With every control in Audit, all tests
are skipped (expected). The first run with `delete_protection` enforced creates the free
canary identity `id-bastion-canary` in `bastion-test-rg`; it stays there on purpose. To see a red run on purpose, set `force_control` to
`storage_shared_key`: the test creates the account (because Audit does not block), fails,
and deletes it.

## Rollback

- A bad policy: set the control back to its audit effect in `policies/effects.json`,
  merge, apply `governance`.
- Remove all of Bastion: see the teardown in [COST.md](COST.md).
