# ADR 0003: Audit before Deny

Date: 2026-11-03, revised 2026-11-04. Status: accepted.

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
   - Disabled for the two DenyAction controls. DenyAction has no audit mode.
3. A control moves to its target effect only after its Audit compliance results have
   been reviewed. Each switch is a separate commit that changes one line in
   `policies/effects.json`. The matching test in `tests/policy` turns on by itself,
   because `run-all.sh` runs a test only when its control is Deny (or DenyAction).
4. Two built-ins have their effect fixed to Deny in the definition (no effect
   parameter), so they cannot start in Audit:
   - Network interfaces should not have public IPs (`83a86a26-fd1f-447c-b59d-e51f44264114`)
   - Require a tag on resources (`871b6d14-10aa-478d-b590-94f262ecfa99`)

   Bastion uses custom copies in `policies/definitions/` with the policy rule unchanged
   and an effect parameter added (Audit, Deny, Disabled; default Audit). The other custom
   definitions exist because no built-in covers the control (see ADR 0004).

## Alternative considered: `enforcementMode: DoNotEnforce`

Microsoft's own rollout mechanism is the assignment property `enforcementMode`. With
`DoNotEnforce`, Azure evaluates the assignment and reports compliance but does not apply
the effect. Microsoft Learn ("Details of the policy assignment structure", Enforcement mode)
recommends it "when you want to evaluate the policy assignment before enforcement", and
the Azure Landing Zones library assigns several guardrails that way.

Bastion does not use it, for three reasons:

1. **Granularity.** Enforcement mode belongs to the assignment, not to each policy inside
   an initiative. ALZ makes one assignment per guardrail, so it can stage each one.
   Bastion has one initiative and wants to move one control at a time, so the switch has
   to be a parameter.
2. **Visibility in Huginn.** The same Learn table says `DoNotEnforce` writes no Activity
   log entry. The Audit effect does write one
   (`Microsoft.Authorization/policies/audit/action`, Policy category, per the Activity
   log schema), and Huginn already collects that category. So the Audit phase can be seen
   and queried in Sentinel, not only in the Policy blade.
3. **One mechanism.** The two fixed-Deny built-ins could only be staged with
   `DoNotEnforce`. Copying them keeps one way of doing it for every control.

The cost of this choice: two custom definitions that must be compared with their source
built-ins when Microsoft updates them (each names its source and version).

Learn also documents a third mode, `Enroll`, which enforces only on resources enrolled in
the assignment. It is not used here.

## Consequences

- Nothing is blocked after Phase 2. The README and `docs/STATUS.md` say so.
- Audit results take time to appear (a compliance scan runs about every 24 hours, or on
  demand with `az policy state trigger-scan`).
