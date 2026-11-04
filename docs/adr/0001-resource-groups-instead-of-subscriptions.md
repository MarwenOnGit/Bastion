# ADR 0001: Resource groups instead of multiple subscriptions

Date: 2026-11-03. Status: accepted.

## Context

A Microsoft Cloud Adoption Framework landing zone separates platform and workloads into
subscriptions (connectivity, management, identity, one per workload) under a management
group hierarchy. Bastion runs on one Azure for Students subscription. Students cannot
create more subscriptions, and the subscription also holds the Huginn and Fenrir labs.

## Decision

1. Each landing-zone area is a resource group in the one subscription:

   | CAF area | Bastion resource group |
   |---|---|
   | Connectivity subscription (hub) | `bastion-hub-rg` |
   | Landing zone subscription (workload) | `bastion-spoke-app-rg` |
   | Sandbox subscription | `bastion-test-rg` |
   | Management subscription (state) | `bastion-tfstate-rg` |
   | Management subscription (logs) | Huginn's `law-huginn`, reused, not owned |

2. Resource groups are the boundary for RBAC (each CI identity is scoped to groups) and
   for policy (bastion-baseline is assigned per group, see ADR 0002).
3. The management group hierarchy (`bastion` > `bastion-platform`,
   `bastion-landing-zones`, `bastion-sandbox`) is created for structure and to show the
   target design. The subscription is **not** moved under it by default.

## Moving the subscription under `bastion-landing-zones` (optional, separate step)

What it would change:

- Anything assigned at a Bastion management group (policy or RBAC) would start applying
  to the whole subscription, **including the Huginn, Fenrir and CTF groups**. Bastion
  assigns nothing at management group scope today, so the move itself changes no
  effective policy. It does make a future mistake there much more dangerous.
- Whoever owns the `bastion` management group becomes an Owner of the subscription by
  inheritance. Only you hold that role.
- Moving needs Owner on the subscription and write rights on the target and source
  management groups (you have both as Global Administrator after elevating access).

Can an Azure for Students subscription be moved? Microsoft does not list Azure for
Students among the offers that cannot join a management group, but I could not reach
Microsoft Learn from the build session to confirm it. **Verify in Azure** with a dry
run in the portal (Management groups > bastion-landing-zones > Add subscription), and
check that the credit and spending limit are unchanged afterwards. If it fails, nothing
else in Bastion depends on it.

To move: set `move_subscription_to_management_group = "landing-zones"` in
`infra/bootstrap` and apply. To undo: set it back to `""` and apply.

## Consequences

- One subscription means one blast radius. RBAC and policy at resource group scope are
  the only separation. This is weaker than subscription separation and is stated as such
  in the README.
- Subscription-scoped features (budget, Defender for Cloud plan, resource provider
  registration) are shared with Huginn and Fenrir. The budget covers everything in the
  subscription, not only Bastion.
