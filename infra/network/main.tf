# ---------------------------------------------------------------------------
# Hub and spoke. No public IPs, no gateways, no firewall.
#
# Hub 10.10.0.0/16
#   10.10.0.0/26    reserved: AzureFirewallSubnet (production design only, not created)
#   10.10.0.64/27   reserved: GatewaySubnet       (production design only, not created)
#   10.10.0.128/26  reserved: AzureBastionSubnet  (production design only, not created)
#   10.10.1.0/24    snet-shared-services          (created, empty)
# Spoke 10.20.0.0/16
#   10.20.1.0/24    snet-app
#   10.20.2.0/24    snet-private-endpoints
#
# Reserved ranges are documented in docs/ARCHITECTURE.md and docs/adr/0007.
# ---------------------------------------------------------------------------

data "azurerm_resource_group" "hub" {
  name = var.hub_resource_group
}

data "azurerm_resource_group" "spoke" {
  name = var.spoke_resource_group
}

locals {
  tags = {
    owner   = var.owner_tag
    env     = "lab"
    project = "bastion"
  }

  hub_subnets = {
    shared-services = cidrsubnet(var.hub_address_space, 8, 1) # 10.10.1.0/24
  }

  spoke_subnets = {
    app               = cidrsubnet(var.spoke_address_space, 8, 1) # 10.20.1.0/24
    private-endpoints = cidrsubnet(var.spoke_address_space, 8, 2) # 10.20.2.0/24
  }

  reserved_hub_ranges = {
    AzureFirewallSubnet = cidrsubnet(var.hub_address_space, 10, 0) # 10.10.0.0/26
    GatewaySubnet       = cidrsubnet(var.hub_address_space, 11, 2) # 10.10.0.64/27
    AzureBastionSubnet  = cidrsubnet(var.hub_address_space, 10, 2) # 10.10.0.128/26
  }
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-bastion-hub"
  resource_group_name = data.azurerm_resource_group.hub.name
  location            = var.location
  address_space       = [var.hub_address_space]
  tags                = local.tags
}

resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-bastion-spoke-app"
  resource_group_name = data.azurerm_resource_group.spoke.name
  location            = var.location
  address_space       = [var.spoke_address_space]
  tags                = local.tags
}

resource "azurerm_subnet" "hub" {
  for_each = local.hub_subnets

  name                            = "snet-${each.key}"
  resource_group_name             = data.azurerm_resource_group.hub.name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = [each.value]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "spoke" {
  for_each = local.spoke_subnets

  name                            = "snet-${each.key}"
  resource_group_name             = data.azurerm_resource_group.spoke.name
  virtual_network_name            = azurerm_virtual_network.spoke.name
  address_prefixes                = [each.value]
  default_outbound_access_enabled = false

  # Apply NSG rules to private endpoints too, so the PE subnet's deny-all is real.
  private_endpoint_network_policies = each.key == "private-endpoints" ? "Enabled" : "Disabled"
}

# Hub <-> spoke peering. No gateway transit, no forwarded traffic.
# There is only one spoke, so there is no spoke-to-spoke path; a second spoke would
# also peer only with the hub.
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "peer-hub-to-spoke-app"
  resource_group_name          = data.azurerm_resource_group.hub.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "peer-spoke-app-to-hub"
  resource_group_name          = data.azurerm_resource_group.spoke.name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
