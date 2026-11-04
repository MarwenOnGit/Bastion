# Five-minute demo

Before the demo: governance and network applied, `storage_shared_key` switched to Deny
and applied (Phase 6), workload applied if you want to show the private endpoints. Open
these tabs in advance: the README, the Azure Policy compliance blade, the GitHub Actions
`policy-tests` workflow, and this repository's PREVENT-DETECT table.

## 0:00 to 1:00: what Bastion is

Open [ARCHITECTURE.md](ARCHITECTURE.md).

- "Bastion is a small landing zone: governance, hub and spoke, private PaaS access, least
  privilege, and a pipeline that proves the guardrails by trying to break them."
- Point at the governance diagram: one subscription, so resource groups play the role of
  subscriptions (ADR 0001). Real effects only on Bastion groups; Huginn, Fenrir and CTF
  groups are excluded (ADR 0002).
- Point at the network diagram: no public IP anywhere, data services only through private
  endpoints, reserved ranges where a firewall and gateway would go.

## 1:00 to 3:00: a policy test going red, then green

The red run was recorded earlier with the control in Audit: Actions > policy-tests >
Run workflow, `force_control = storage_shared_key`. Show it:

- "Audit blocks nothing, so Azure accepted a storage account with shared keys enabled.
  The test failed, and its trap deleted the account."

Now the green run (control in Deny): Actions > policy-tests > Run workflow, empty input.
While it runs (about a minute), explain the test in
[test-storage-shared-key.sh](../tests/policy/test-storage-shared-key.sh):

- One ARM PUT, as `bastion-policy-tester`, which is Contributor on `bastion-test-rg` only.
- It passes only on `RequestDisallowedByPolicy` naming `bastion-baseline` and
  `storage-shared-key`. Any other error is a failure.

Show the job summary table: PASS for `storage_shared_key`, skipped for controls still in
Audit.

## 3:00 to 4:00: the compliance view

Azure portal > Policy > Compliance > `Bastion baseline (bastion-spoke-app-rg)`, or the
compliance report in the last `drift` run's summary.

- Controls still in Audit show their non-compliant resources here instead of blocking.
- Diagnostic settings: after the switch to DeployIfNotExists, the Key Vault has a setting
  named `bastion-to-law-huginn`, so its logs land in Huginn's Sentinel workspace.

## 4:00 to 5:00: prevent and detect

Open [PREVENT-DETECT.md](PREVENT-DETECT.md).

- "Bastion prevents, Huginn detects." Walk P-12: Bastion makes `listKeys` useless (shared
  keys off), Huginn's `storage-keys-listed` still alerts on the attempt.
- Walk X-08: Policy cannot block Run Command, so Bastion uses RBAC (Bastion VM Operator),
  and Huginn's `vm-runcommand-by-user` catches anyone who still has Contributor.
- Show that a blocked attempt is also a detection: the KQL in PREVENT-DETECT lists the
  denials from the policy tests in `law-huginn`.
- End on the gaps: no Entra ID P1, so no Conditional Access, PIM or sign-in logs. Said
  plainly, with the fix (licence) named.

## If something goes wrong live

- A test fails for a reason other than policy: show the log; the cleanup step still ran.
- Azure is slow: use the recorded green run.
