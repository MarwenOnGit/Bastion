# Cost

Subscription: Azure for Students. Region: francecentral. Prices are rough pay-as-you-go
list prices in USD, checked from memory on 2026-11-03 because the pricing pages were not
reachable from the build session. **Verify in the Azure pricing calculator.**

## What costs nothing

Management groups, Azure Policy (definitions, assignments, compliance), RBAC, custom
roles, app registrations and federated credentials, user-assigned managed identities,
resource groups, VNets, subnets, NSGs, VNet peering (the resource itself), budgets,
Defender for Cloud foundational CSPM, GitHub Actions minutes on a public repository.

## Expected monthly cost

| Item | Stack | Always on? | Monthly |
|---|---|---|---|
| State storage account (a few KB, versioned) | bootstrap | yes | < $0.10 |
| 2 private DNS zones ($0.50 each) | network | yes | $1.00 |
| VNet peering data ($0.01/GB each way, intra-region) | network | yes | about $0 (no traffic) |
| Diagnostic logs into `law-huginn` (Key Vault, NSG, blob: well under 1 GB) | governance | yes | < $0.50, ingestion may be inside the workspace's free allowance (verify) |
| **Always-on total** | | | **about $1.50** |
| 2 private endpoints ($0.01/hour each) | workload | no, demo only | $14.60 if left on all month |
| Storage account and Key Vault (almost no data, few operations) | workload | no, demo only | < $0.20 |
| **Workload, if left on all month** | | | **about $15** |
| Policy tests (Deny means nothing is created; a wrongly created resource lives for under a minute) | tests | nightly | about $0 |

Workload for a one-hour demo: about $0.03.

**Recommendation:** keep governance and network up, and apply the workload stack only for
demos, then destroy it. Two private endpoints left on for a year would use about $175,
which is more than a typical Azure for Students credit.

The budget (default $20 a month, `budget_amount` in `infra/governance`) alerts at 50%, 80%
and 100% of actual cost and at 100% of forecast. A budget only alerts; it never stops
anything. It covers the whole subscription, including Huginn and Fenrir.

Never deployed (see ADR [0007](adr/0007-no-firewall-gateway-or-azure-bastion-service.md)), and
blocked in the Bastion groups by the `denied_resource_types` control once it is Deny:
Azure Firewall, the Azure Bastion service, VPN or ExpressRoute gateways, DDoS Network
Protection, Application Gateway, paid Defender plans, VMs.

## Teardown

Destroy in reverse order. From GitHub (Actions > apply > Run workflow, on main), each run
needs your approval:

1. stack `workload`, operation `destroy`, confirm `workload`
2. stack `network`, operation `destroy`, confirm `network`
3. stack `governance`, operation `destroy`, confirm `governance`

The governance destroy removes the policy assignments first, which also turns off the two
DenyAction controls. Then delete the policy-test canary (it is not in Terraform state, and
while `delete_protection` was on it could not be deleted):

```bash
az identity delete --resource-group bastion-test-rg --name id-bastion-canary
```

Then on your laptop:

```bash
terraform -chdir=infra/bootstrap destroy
```

The bootstrap destroy also removes the `CanNotDelete` lock on `law-huginn`; until then
Huginn's own teardown cannot delete its workspace.

Notes:

- The Key Vault has purge protection. After destroy it stays soft-deleted for 7 days (no
  charge) and its name cannot be reused until then. A new apply recovers it automatically.
- The bootstrap destroy removes the state account, so destroy the other stacks first.
- If the bootstrap destroy is refused with a 403 from `bastion-baseline`, the governance
  stack is still applied: `delete_protection` protects `id-bastion-policy`. Destroy
  governance first.
- If GitHub is unavailable, the same teardown works locally after `az login`:

  ```bash
  for s in workload network governance; do terraform -chdir=infra/$s init -backend-config="storage_account_name=<TFSTATE_STORAGE_ACCOUNT>" && terraform -chdir=infra/$s destroy; done
  ```
