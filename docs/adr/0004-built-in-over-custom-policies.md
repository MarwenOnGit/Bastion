# ADR 0004: Built-in policy definitions over custom ones

Date: 2026-11-03, revised 2026-11-04. Status: accepted.

## Decision

Use a built-in definition whenever one exists. Write a custom definition only when no
built-in can express the control in the way Bastion needs.

Today the initiative references 23 built-ins and 6 custom definitions:

- 2 copies of built-ins whose effect is fixed to Deny, so they can start in Audit
  (ADR 0003);
- 2 copies of Azure Landing Zones definitions (subnets need an NSG, no management ports
  from the internet), for which no built-in has a Deny effect;
- 2 DenyAction definitions, one copied from ALZ and one following an ALZ pattern, because
  no built-in DenyAction exists for them.

When a custom definition is needed, the second choice after a built-in is a definition
Microsoft already maintains in the Azure Landing Zones library, copied with its MIT
attribution and with the rule unchanged.

Every built-in was checked against the source of the published definitions,
github.com/Azure/azure-policy, commit `f096d8d` (2026-10-28): GUID, display name,
version, allowed effects and parameter names. The check is repeatable: see "How the IDs
were verified" in [POLICIES.md](../POLICIES.md).

## Why

- Microsoft maintains built-ins as resource providers change (new API versions, new
  aliases). A custom copy freezes the rule.
- Built-ins have stable GUIDs that reviewers can look up.
- Compliance in the portal groups built-ins with Microsoft's documentation.

## Consequences

- The custom copies must be compared against their sources (built-in or ALZ) when
  Microsoft updates them. Each custom file names its source and version in `metadata.source`.
- There is no built-in Deny for App Service basic auth (only AuditIfNotExists and
  DeployIfNotExists). Bastion uses the built-ins and accepts that this control fixes
  apps after creation rather than blocking them (see POLICIES.md).
