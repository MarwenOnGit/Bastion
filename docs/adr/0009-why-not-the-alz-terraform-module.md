# ADR 0009: Hand-written Terraform instead of the ALZ modules, AVM or EPAC

Date: 2026-11-04. Status: accepted.

## Context

Microsoft publishes production-grade ways to build a landing zone:

- **Azure Landing Zones Terraform and Bicep implementations** (the ALZ accelerator and
  the `Azure/avm-ptn-alz` pattern module), which deploy the management group hierarchy,
  the ALZ policy library and the platform networking.
- **Azure Verified Modules (AVM)**, Microsoft-supported Terraform and Bicep modules for
  single resources (VNet, Key Vault, storage) and for patterns.
- **Enterprise Policy as Code (EPAC)**, Microsoft's PowerShell-based framework for
  managing policy definitions, assignments and exemptions across environments.

## Decision

Bastion is hand-written with plain `azurerm` resources and a JSON policy source of truth,
and borrows from those projects instead of depending on them:

- policy definitions and assignment choices come from the ALZ library, copied with
  attribution where needed (MIT), and compared one by one in
  [ALZ-ALIGNMENT.md](../ALZ-ALIGNMENT.md);
- the policy-as-code flow (definitions and assignments in source control, plan, review,
  apply, compliance reporting) follows the same stages EPAC uses, in about 300 lines.

## Why

1. **One subscription, resource-group scope.** The ALZ modules assume management group
   scope and several subscriptions. Assigning their archetypes at the root of this tenant
   would apply to the Huginn, Fenrir and CTF groups, which ADR
   [0002](0002-policy-scope-and-exclusions.md) forbids.
2. **Cost.** The ALZ connectivity defaults include Azure Firewall, gateways and DDoS
   protection, which must all be turned off for Azure for Students.
3. **Every line is explainable.** This is a learning and portfolio project. Each control
   has a test, an ADR and a Fenrir mapping. A dependency that brings hundreds of
   policies, most of which do not apply, would hide the reasoning.
4. **No registry in the build session.** Module downloads from the Terraform registry
   were blocked during development, so modules could not have been validated locally.

## Consequences

- Bastion has to follow upstream changes by hand. Each copied definition names its source
  and version.
- Moving to the real ALZ later is a mapping exercise: every Bastion control names the ALZ
  assignment that replaces it, and CAF's single-subscription scenario describes the move
  (deploy ALZ in parallel, then move workloads into new subscriptions).
- For a team with several subscriptions, the ALZ accelerator or `avm-ptn-alz` and EPAC are
  the better starting point. Bastion says so in its README.
