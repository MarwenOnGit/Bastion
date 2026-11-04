# Alignment with Azure landing zones

Bastion is a deliberately small landing zone. This page compares it with Microsoft's
reference, the Azure landing zone in the Cloud Adoption Framework (CAF), so a reader can
see what was adopted, what was adapted for one Azure for Students subscription, and what
was left out on purpose.

Sources, read on 2026-11-04 from their public repositories (learn.microsoft.com itself
was not reachable from the build session):

- CAF, "Azure landing zone design areas" and "Transition a single subscription with no
  management groups" (MicrosoftDocs/cloud-adoption-framework, commit `6535103`).
- Azure Landing Zones Library, the policy and archetype definitions that the ALZ
  Terraform and Bicep implementations deploy (Azure/Azure-Landing-Zones-Library, commit
  `124b242`, MIT licence).

## The eight design areas

| CAF design area | What ALZ recommends | What Bastion does | Gap or adaptation |
|---|---|---|---|
| Azure billing and Microsoft Entra tenant | Enterprise enrolment, a dedicated tenant | A personal tenant on Azure for Students; budget with 50/80/100% alerts | No enrolment hierarchy; one subscription. ADR [0001](adr/0001-resource-groups-instead-of-subscriptions.md) |
| Identity and access management | Least privilege, PIM for privileged roles, Conditional Access, workload identities without secrets | Three OIDC identities, no stored credentials anywhere, least-privilege roles per resource group, custom role without Run Command or exec | No Entra ID P1/P2, so no PIM and no Conditional Access. You keep a standing Owner. ADRs [0005](adr/0005-oidc-with-id-based-subjects.md), [0006](adr/0006-ci-identities-and-least-privilege.md), [0008](adr/0008-rbac-for-actions-policy-cannot-block.md) |
| Resource organization | Management group hierarchy (platform, landing zones, sandbox, decommissioned), one subscription per workload | Hierarchy `bastion` > `platform`, `landing-zones`, `sandbox`; resource groups stand in for subscriptions | CAF itself describes a single subscription with per-resource-group policy and RBAC as a valid starting state, and its transition path is to deploy ALZ in parallel. That is Bastion's roadmap |
| Network topology and connectivity | Hub and spoke or Virtual WAN; firewall and gateways in the hub; private DNS zones in the hub; Private Link for PaaS | Hub and spoke, private DNS zones in the hub linked to both VNets, private endpoints for blob and vault, NSG on every subnet, no default outbound access | No firewall, gateway, Azure Bastion service or DDoS plan (cost). Their subnets are reserved. ADR [0007](adr/0007-no-firewall-gateway-or-azure-bastion-service.md) |
| Security | Microsoft Defender for Cloud, MCSB, encryption, key management | Defender for Cloud foundational CSPM (free), security contact, every control mapped to MCSB v2, Key Vault with RBAC and purge protection | No paid Defender plans |
| Management | Central Log Analytics, Activity log export, diagnostic settings by policy | Reuses Huginn's `law-huginn` (Huginn already exports the Activity log, including the Policy category). DeployIfNotExists diagnostic settings for Key Vault, NSG and blob. Diagnostic settings cannot be deleted (DenyAction) | No Azure Monitor Agent or update management: there are no VMs |
| Governance | Policy-driven guardrails, assigned at management group scope, rolled out with `DoNotEnforce` first | `bastion-baseline`: 21 controls, built-ins first, Audit first, assigned at resource group scope | Resource group scope instead of management group (ADR [0002](adr/0002-policy-scope-and-exclusions.md)); effect parameters instead of `DoNotEnforce` (ADR [0003](adr/0003-audit-before-deny.md)) |
| Platform automation and DevOps | Infrastructure as code, CI/CD with approvals, policy as code | Terraform, GitHub Actions with OIDC, environment approval for apply, nightly drift and compliance, conftest, a live policy test for every enforcing control | Smaller than the ALZ accelerator, on purpose (ADR [0009](adr/0009-why-not-the-alz-terraform-module.md)) |

## ALZ policy assignments, one by one

The ALZ library assigns these to the "landing zones" and "corp" management groups (the
ones a workload like Bastion's spoke would live under), plus a few at the root. Only the
assignments relevant to resources Bastion can have are listed.

| ALZ assignment | Definition | In Bastion? | Notes |
|---|---|---|---|
| Deny-Subnet-Without-Nsg | ALZ custom | yes, `subnet_nsg` | Copied (MIT). It is why Bastion declares subnets inline: a separate subnet resource is created before its NSG association and would be denied |
| Deny-MgmtPorts-Internet | ALZ custom | yes, `mgmt_ports_internet` | Copied (MIT), ports 22 and 3389 |
| Enforce-Subnet-Private | `7bca8353...` | yes, `subnet_private` | ALZ assigns it with `DoNotEnforce`; Bastion targets Deny because every subnet already sets `default_outbound_access_enabled = false` |
| Deny-Storage-http | `404c3081...` | yes, `storage_secure_transfer` | |
| Deny-Public-IP-On-NIC (corp) | `83a86a26...` | yes, `nic_no_public_ip` | Custom copy, so it can start in Audit |
| Deny-Public-Endpoints (corp) | initiative of 25+ "public network access disabled" built-ins | partly: storage and Key Vault | Bastion only has those two PaaS services |
| Deploy-Private-DNS-Zones (corp) | DeployIfNotExists per Private Link zone | no | Bastion creates its two zones and DNS zone groups in Terraform; with two endpoints a policy adds nothing |
| Enforce-GR-KeyVault | initiative | partly: purge protection, RBAC model, public access | The rest (key and secret expiry, key sizes) needs data-plane objects Bastion does not create |
| Enforce-GR-Storage | initiative | partly: shared key, public access, TLS, HTTPS, anonymous blobs | |
| Deny-IP-forwarding | `88c0b9da...` | no | No NICs exist; `denied_resource_types` blocks VMs |
| Deny-Classic-Resources | `6c112d4e...` (Not allowed resource types) | same built-in, different list | Bastion's list is cost and exposure: appliances, public IPs, VMs |
| DenyAction-DiagnosticLogs | ALZ custom | yes, `protect_diagnostic_settings` | Copied, with an effect parameter added |
| DenyAction-DeleteUAMIAMA | DenyAction on the AMA identity | same idea, `delete_protection` | Protects Bastion's policy remediation identity instead |
| Deploy-AzActivity-Log (root) | `2465583e...` | not needed | Huginn already exports the subscription Activity log to `law-huginn` |
| Deploy-MDFC-Config (root) | Defender for Cloud plans and settings | partly | Foundational CSPM (free) and a security contact; no paid plans |
| Enforce-ACSB, Deploy-VM-*, Deploy-SQL-*, AKS guardrails | VM, SQL, AKS | no | Bastion has none of those resources |
| Enable-DDoS-VNET (connectivity) | DDoS plan | no | About $2,950 a month |

Bastion also adds controls that ALZ does not assign by default: required tags, allowed
locations, ACR admin user, App Service basic auth (ALZ has these inside its App Service
and Container Registry guardrail initiatives), and DenyAction on any resource tagged
`bastion-protected`.

## Rollout method: `DoNotEnforce` versus effect parameters

ALZ stages many guardrails by assigning them with `enforcementMode: DoNotEnforce`, then
switching to `Default`. Microsoft Learn recommends `DoNotEnforce` "when you want to
evaluate the policy assignment before enforcement". Bastion uses effect parameters
instead (Audit, then Deny). The reasons are in ADR
[0003](adr/0003-audit-before-deny.md); in short:

1. Enforcement mode is per assignment. ALZ makes one assignment per guardrail, so it can
   stage each one. Bastion has one initiative, so an effect parameter is the per-control
   switch.
2. With `DoNotEnforce`, Azure writes no Activity log entry for the evaluation. With the
   Audit effect it does (`Microsoft.Authorization/policies/audit/action`), and Huginn
   already collects the Policy category, so the Audit phase is visible in Sentinel.
3. Two built-ins have no effect parameter at all, so for them `DoNotEnforce` would have
   been the only option without a custom copy. Bastion copies them instead, to keep one
   mechanism.

## When Bastion would move to the real ALZ

CAF's single-subscription scenario recommends deploying the ALZ reference architecture in
parallel, in the same tenant, then moving workloads into new subscriptions. Bastion's
management groups, its control list and its ADRs are written so that move is mostly a
mapping: each Bastion control above names the ALZ assignment that replaces it. See ADR
[0009](adr/0009-why-not-the-alz-terraform-module.md).
