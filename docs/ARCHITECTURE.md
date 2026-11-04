# Architecture

The Bastion landing zone in one subscription. This project does not deploy the Azure
Bastion service (Microsoft's jump-host product); "Bastion" here is the landing zone's name.

## Governance

```mermaid
flowchart TB
  root["Tenant Root Group"]
  root --> mg["bastion"]
  mg --> plat["bastion-platform"]
  mg --> lz["bastion-landing-zones"]
  mg --> sb["bastion-sandbox"]
  root --> sub["Subscription 42146134-... (Azure for Students)<br/>stays under the root unless moved (ADR 0001)"]

  sub --> defs["Policy definitions at subscription scope<br/>bastion-baseline initiative (21 controls)<br/>23 built-ins + 6 custom definitions"]
  sub --> budget["Budget bastion-monthly<br/>50% / 80% / 100% actual, 100% forecast"]
  sub --> cspm["Defender for Cloud<br/>foundational CSPM (Free)"]

  subgraph bastion_rgs["Bastion resource groups (bastion-baseline assigned here)"]
    hub["bastion-hub-rg<br/>platform / connectivity"]
    spoke["bastion-spoke-app-rg<br/>landing zone / workload"]
    test["bastion-test-rg<br/>sandbox / policy tests"]
  end
  state["bastion-tfstate-rg<br/>state, owned by the bootstrap<br/>(no assignment, ADR 0002)"]

  subgraph protected["Protected groups: never modified, excluded from every assignment"]
    h1["huginn-lab-rg"]
    h2["huginn-sentinel-rg<br/>law-huginn + Sentinel"]
    h3["huginn-tfstate-rg"]
    f1["fenrir-lab-prod-rg"]
    c1["ctf-*"]
  end

  defs -. "assigned with real effects" .-> bastion_rgs
  bastion_rgs -. "diagnostic settings (DeployIfNotExists)" .-> h2
```

## Network

```mermaid
flowchart LR
  subgraph hubrg["bastion-hub-rg"]
    subgraph hub["vnet-bastion-hub 10.10.0.0/16"]
      fw["10.10.0.0/26 AzureFirewallSubnet<br/>(reserved, not created)"]
      gw["10.10.0.64/27 GatewaySubnet<br/>(reserved, not created)"]
      ab["10.10.0.128/26 AzureBastionSubnet<br/>(reserved, not created)"]
      shared["10.10.1.0/24 snet-shared-services<br/>NSG: deny all in"]
    end
    dnsb["privatelink.blob.core.windows.net"]
    dnsv["privatelink.vaultcore.azure.net"]
    uai["id-bastion-policy<br/>(policy remediation identity)"]
  end

  subgraph spokerg["bastion-spoke-app-rg"]
    subgraph spoke["vnet-bastion-spoke-app 10.20.0.0/16"]
      app["10.20.1.0/24 snet-app<br/>NSG: deny all in"]
      pe["10.20.2.0/24 snet-private-endpoints<br/>NSG: 443 from snet-app and hub shared only"]
    end
    st["Storage account<br/>public access off, shared key off"]
    kv["Key Vault<br/>public access off, RBAC"]
  end

  hub <-- "peering (no gateway transit, no forwarded traffic)" --> spoke
  pe -- "private endpoint (blob)" --> st
  pe -- "private endpoint (vault)" --> kv
  dnsb -. linked .- hub
  dnsb -. linked .- spoke
  dnsv -. linked .- hub
  dnsv -. linked .- spoke
```

No public IP exists anywhere. The internet cannot reach anything in Bastion, and the
workload's data services cannot be reached from the internet either.

### NSG rules

Every subnet has its own NSG. Every NSG ends in two explicit rules at priority 4096:
`deny-all-inbound` and `deny-all-outbound`. They make the intent visible and override
Azure's defaults (`AllowVnetInBound`, `AllowInternetOutBound`).

| NSG | Allowed (priority) | Why |
|---|---|---|
| `nsg-bastion-hub-shared-services` | out 443 to snet-private-endpoints (100) | reach the private endpoints |
| | out 443 to `AzureActiveDirectory` (110) | get Entra ID tokens |
| | out 443 to `AzureMonitor` (120) | send logs and metrics |
| `nsg-bastion-spoke-app` | same three outbound rules | same reasons |
| `nsg-bastion-spoke-private-endpoints` | in 443 from snet-app (100) and from hub shared services (110) | the only clients of the data services |

The PE subnet sets `private_endpoint_network_policies = "Enabled"` so these NSG rules
actually apply to private endpoint traffic.

Subnets are declared inline in each VNet with their NSG (`security_group`), not as separate
`azurerm_subnet` resources. A separate subnet is created first and associated with its NSG
afterwards, and in between it would violate the `subnet_nsg` control (Azure Landing Zones
`Deny-Subnet-Without-Nsg`). Every subnet also sets `default_outbound_access_enabled = false`
(the `subnet_private` control), so nothing in it can reach the internet through Azure's
implicit outbound IP.

Two things to know:

- Azure DNS (168.63.129.16) and the instance metadata service are platform traffic and are
  not affected by NSGs.
- `deny-all-inbound` also blocks the `AzureLoadBalancer` health probe. A load-balanced
  workload would need an allow rule for it.

### Where a firewall and a gateway would sit

See ADR [0007](adr/0007-no-firewall-gateway-or-azure-bastion-service.md). In a production
design, Azure Firewall goes in `AzureFirewallSubnet` with a 0.0.0.0/0 route from each
spoke, a VPN or ExpressRoute gateway goes in `GatewaySubnet`, and the spokes use remote
gateways through the peering.

## Delivery

```mermaid
flowchart LR
  dev["push to bastion-dev"] --> ci["ci.yml<br/>fmt, validate, tflint,<br/>checkov, conftest verify, pytest<br/>(no Azure access)"]
  dev --> plan["plan.yml<br/>bastion-github-plan<br/>Reader + state reader<br/>plan -lock=false + conftest"]
  pr["pull request to main"] --> ci
  pr --> plan
  merge["you merge to main"] --> apply["apply.yml (manual)<br/>environment bastion-apply<br/>you approve<br/>plan + conftest gate + apply"]
  nightly["nightly on main"] --> drift["drift.yml<br/>bastion-github-plan<br/>red if Azure changed"]
  nightly --> ptest["policy-tests.yml<br/>environment bastion-policy-tests<br/>bastion-policy-tester<br/>Contributor on bastion-test-rg only"]
  laptop["your laptop"] --> boot["infra/bootstrap<br/>identities, roles, state, MGs<br/>(local state)"]
```

All Azure logins use OIDC with ID-based subjects (ADR
[0005](adr/0005-oidc-with-id-based-subjects.md)). Roles are in ADR
[0006](adr/0006-ci-identities-and-least-privilege.md).

## Stacks and state

| Stack | Who runs it | State |
|---|---|---|
| `infra/bootstrap` | you, on your laptop | local file, git-ignored |
| `infra/governance` | `apply.yml` | `bastion-tfstate-rg` / `tfstate` / `governance.tfstate` |
| `infra/network` | `apply.yml` | `.../network.tfstate` |
| `infra/workload` | `apply.yml` | `.../workload.tfstate` |

The state account allows Entra ID only (shared keys disabled, no SAS, no anonymous blob
access, TLS 1.2), with blob versioning and 14-day soft delete. It keeps a public endpoint
because GitHub-hosted runners have no private path into the VNet; access depends on Entra
ID and the data role on the container. Its blob logs go to `law-huginn`.

Stacks do not read each other's state. The network and workload stacks find what they
need with data sources by name, and names are derived from the subscription ID.
