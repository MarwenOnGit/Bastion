# ADR 0007: No firewall, gateway or Azure Bastion service

Date: 2026-11-03. Status: accepted.

## Context

Azure for Students gives a small credit. The services a production hub normally holds
cost more per month than the whole credit:

| Service | Rough monthly cost (pay-as-you-go, Europe) |
|---|---|
| Azure Firewall Basic / Standard | about $290 / $910 |
| VPN Gateway (VpnGw1) | about $140 |
| ExpressRoute gateway | about $140 and up, plus a circuit |
| Azure Bastion service (Basic) | about $140 |
| DDoS Network Protection | about $2,950 |
| Application Gateway v2 | about $180 and up |

Figures are rough list prices for comparison only. Verify in the Azure pricing calculator.

## Decision

None of them is deployed. Hub ranges are reserved so they could be added without
renumbering:

| Range | Reserved for |
|---|---|
| 10.10.0.0/26 | AzureFirewallSubnet |
| 10.10.0.64/27 | GatewaySubnet |
| 10.10.0.128/26 | AzureBastionSubnet (the Microsoft jump-host service) |

Three layers keep them out:

- `tests/static/test_terraform.py` rejects the code;
- `opa/bastion.rego` rejects a plan that contains them;
- the `denied_resource_types` policy control (built-in "Not allowed resource types",
  `6c112d4e-5bc7-47ae-a041-ea2d9dccd749`) makes Azure itself refuse them in the Bastion
  groups once it is in Deny, whoever deploys and however.

## Where they would sit in production

- **Azure Firewall** in the hub, with a route table on every spoke subnet sending
  0.0.0.0/0 to it. Spoke-to-spoke and spoke-to-internet traffic is then inspected and
  logged in one place. In Bastion, NSGs deny all outbound traffic except to the private
  endpoints, Entra ID and Azure Monitor, which is the closest free equivalent.
- **VPN or ExpressRoute gateway** in GatewaySubnet, with peering set to "use remote
  gateways" in the spokes, for on-premises access.
- **Azure Bastion service** in AzureBastionSubnet, for browser-based SSH or RDP to VMs
  without public IPs. Bastion has no VMs in its always-on design, so there is nothing to
  connect to.
- **DDoS Network Protection** on the hub VNet, once there is a public endpoint to protect.
  Bastion has none.
