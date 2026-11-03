# ADR 0004: Built-in policy definitions over custom ones

Date: 2026-11-03. Status: accepted.

## Decision

Use a built-in definition whenever one exists. Write a custom definition only when no
built-in can express the control in the way Bastion needs.

Today the initiative references 16 built-ins and 2 custom definitions. The custom ones are
copies of built-ins whose effect is fixed to Deny (ADR 0003).

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

- The two custom copies must be compared against their source built-ins when Microsoft
  updates them. Each custom file names its source and version in `metadata.source`.
- There is no built-in Deny for App Service basic auth (only AuditIfNotExists and
  DeployIfNotExists). Bastion uses the built-ins and accepts that this control fixes
  apps after creation rather than blocking them (see POLICIES.md).
