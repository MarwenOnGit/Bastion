# ADR 0003: Audit before Deny

Date: 2026-11-03. Status: accepted.

## Context

A Deny policy that is wrong breaks deployments, and a DeployIfNotExists policy that is
wrong changes resources. Both are hard to debug if they arrive at the same time as the
resources they govern.

## Decision

1. Every control in `bastion-baseline` has its own effect parameter
   (`effect_<control>`). `policies/effects.json` holds the current value for each one.
2. Phase 2 sets every control to its audit effect:
   - Audit for controls that target Deny.
   - AuditIfNotExists for the diagnostic-settings control (target DeployIfNotExists) and
     for the App Service basic-auth report.
   - Disabled for the App Service basic-auth fix, whose built-ins only allow
     DeployIfNotExists or Disabled.
3. A control moves to its target effect only after its Audit compliance results have
   been reviewed. Each switch is a separate commit that changes one line in
   `policies/effects.json`. The matching test in `tests/policy` turns on by itself,
   because `run-all.sh` runs a test only when its control is Deny.
4. Two built-ins have their effect fixed to Deny in the definition (no effect
   parameter), so they cannot start in Audit:
   - Network interfaces should not have public IPs (`83a86a26-fd1f-447c-b59d-e51f44264114`)
   - Require a tag on resources (`871b6d14-10aa-478d-b590-94f262ecfa99`)

   Bastion uses custom copies in `policies/definitions/` with the policy rule unchanged
   and an effect parameter added (Audit, Deny, Disabled; default Audit). This is the only
   reason Bastion has custom definitions (see ADR 0004).

## Consequences

- Nothing is blocked after Phase 2. The README and `docs/STATUS.md` say so.
- Audit results take time to appear (a compliance scan runs about every 24 hours, or on
  demand with `az policy state trigger-scan`).
