# ADR 0002: Policy scope and exclusions

Date: 2026-11-03. Status: accepted.

## Context

The subscription also holds labs that must keep working:

- `fenrir-lab-prod-rg` is deliberately insecure. A Deny policy there would break it.
- `huginn-lab-rg`, `huginn-sentinel-rg`, `huginn-tfstate-rg` belong to Huggin.
- Any group starting with `ctf-` belongs to CTF work.

## Decision

1. **Definitions** (two custom definitions and the `bastion-baseline` initiative) live at
   subscription scope. They have no effect until assigned.
2. **Assignments with real effects** (Deny, DeployIfNotExists) are made only at the
   Bastion resource groups: `bastion-hub-rg`, `bastion-spoke-app-rg`, `bastion-test-rg`.
   The Terraform variable has a validation that rejects any group not starting with
   `bastion-`, and `opa/bastion.rego` rejects a plan that assigns to another group.
3. **No management group assignment** at all.
4. **An optional subscription assignment** (`enable_subscription_audit`, off by default)
   exists only to report compliance across the subscription. Every effect is forced to its
   audit value whatever `policies/effects.json` says, and `not_scopes` lists every
   protected group. conftest rejects a subscription assignment that has a non-audit effect
   or is missing an exclusion.
5. `not_scopes` has no wildcards, so `ctf-*` cannot be expressed. Existing `ctf-` groups
   must be listed in `existing_prefixed_protected_groups`. A `ctf-` group created later is
   **not** excluded until it is added. Because that assignment is audit-only, the worst
   case is a compliance report on a CTF group, never a blocked or changed resource.
6. The policy identity `id-bastion-policy` has roles only on the three Bastion groups (and
   Log Analytics Contributor on `law-huginn` to point diagnostic settings at it). Even a
   wrongly configured DeployIfNotExists could not deploy into a protected group.
7. `bastion-tfstate-rg` is not in the assignment list: the bootstrap owns it, and a Deny
   there could lock the pipeline out of its own state.

## Consequences

- Resources created outside the Bastion groups are not governed by Bastion. That is the
  point: Bastion is a landing zone next to the labs, not over them.
- The real effects of each control are tested only in `bastion-test-rg` (Phase 5).
