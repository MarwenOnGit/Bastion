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

- Creating management groups under the Tenant Root Group: if the hierarchy settings
  require write access on the root, elevate access first (Entra ID > Properties > Access
  management for Azure resources > Yes), and turn it off again after step 2.

## 2. Bootstrap (once)

Read the plan before you apply it. It creates 5 resource groups (including
`bastion-identity-rg`, which holds only the policy identity), the state account, 3 app
registrations with federated credentials, role assignments, custom roles, 1 managed
identity, 4 management groups and a diagnostic setting on the state account. Outside
Bastion's groups it makes exactly two writes, both on `law-huginn`: a role assignment
(Bastion Diagnostics Destination) and a `CanNotDelete` lock.

**The lock on `law-huginn` affects the Huginn repo.** While it exists, nobody can delete
the workspace, including `terraform destroy` or a replacement in the Huginn repo.
Microsoft Learn ("Lock your resources") says extension resources inherit a lock from the
resource they are applied to, so deleting resources scoped on the workspace (for example
Sentinel content Huginn manages) may be refused too: verify in Azure. A delete lock does
not stop data purge. To remove the lock, set `lock_huginn_workspace = false` in
`infra/bootstrap` and apply the bootstrap, then make the Huginn change, then turn it back
on.

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
