# ---------------------------------------------------------------------------
# One NSG per subnet. Every NSG ends with an explicit deny-all inbound rule, so
# the intent is visible and does not depend on Azure's default rules
# (AllowVnetInBound at 65000 would otherwise allow all VNet traffic, including
# from the peered hub).
#
# Outbound is deny-by-default too. The few allowed flows are listed per subnet and
# explained in docs/ARCHITECTURE.md.
#
# Note: deny-all inbound also blocks the AzureLoadBalancer health probe tag. Add
# an allow rule for it if a load-balanced workload is ever placed in a subnet.
# ---------------------------------------------------------------------------

locals {
  hub_prefix_shared = local.hub_subnets["shared-services"]
  spoke_prefix_app  = local.spoke_subnets["app"]
  spoke_prefix_pe   = local.spoke_subnets["private-endpoints"]

  nsg_rules = {
    hub-shared-services = {
      rg = "hub"
      rules = [
        { name = "allow-out-pe-https", priority = 100, direction = "Outbound", access = "Allow", protocol = "Tcp", src = local.hub_prefix_shared, dst = local.spoke_prefix_pe, port = "443" },
        { name = "allow-out-entra-id", priority = 110, direction = "Outbound", access = "Allow", protocol = "Tcp", src = local.hub_prefix_shared, dst = "AzureActiveDirectory", port = "443" },
        { name = "allow-out-azure-monitor", priority = 120, direction = "Outbound", access = "Allow", protocol = "Tcp", src = local.hub_prefix_shared, dst = "AzureMonitor", port = "443" },
        { name = "deny-all-outbound", priority = 4096, direction = "Outbound", access = "Deny", protocol = "*", src = "*", dst = "*", port = "*" },
        { name = "deny-all-inbound", priority = 4096, direction = "Inbound", access = "Deny", protocol = "*", src = "*", dst = "*", port = "*" },
      ]
    }
    spoke-app = {
      rg = "spoke"
      rules = [
        { name = "allow-out-pe-https", priority = 100, direction = "Outbound", access = "Allow", protocol = "Tcp", src = local.spoke_prefix_app, dst = local.spoke_prefix_pe, port = "443" },
        { name = "allow-out-entra-id", priority = 110, direction = "Outbound", access = "Allow", protocol = "Tcp", src = local.spoke_prefix_app, dst = "AzureActiveDirectory", port = "443" },
        { name = "allow-out-azure-monitor", priority = 120, direction = "Outbound", access = "Allow", protocol = "Tcp", src = local.spoke_prefix_app, dst = "AzureMonitor", port = "443" },
        { name = "deny-all-outbound", priority = 4096, direction = "Outbound", access = "Deny", protocol = "*", src = "*", dst = "*", port = "*" },
        { name = "deny-all-inbound", priority = 4096, direction = "Inbound", access = "Deny", protocol = "*", src = "*", dst = "*", port = "*" },
      ]
    }
    spoke-private-endpoints = {
      rg = "spoke"
      rules = [
        { name = "allow-in-https-from-app", priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp", src = local.spoke_prefix_app, dst = local.spoke_prefix_pe, port = "443" },
        { name = "allow-in-https-from-hub-shared", priority = 110, direction = "Inbound", access = "Allow", protocol = "Tcp", src = local.hub_prefix_shared, dst = local.spoke_prefix_pe, port = "443" },
        { name = "deny-all-inbound", priority = 4096, direction = "Inbound", access = "Deny", protocol = "*", src = "*", dst = "*", port = "*" },
        # Private endpoints never start connections.
        { name = "deny-all-outbound", priority = 4096, direction = "Outbound", access = "Deny", protocol = "*", src = "*", dst = "*", port = "*" },
      ]
    }
  }

  nsg_rule_list = merge([
    for nsg_key, nsg in local.nsg_rules : {
      for r in nsg.rules : "${nsg_key}/${r.name}" => merge(r, { nsg = nsg_key })
    }
  ]...)

  nsg_rg = {
    hub   = data.azurerm_resource_group.hub.name
    spoke = data.azurerm_resource_group.spoke.name
  }
}

resource "azurerm_network_security_group" "this" {
  for_each = local.nsg_rules

  name                = "nsg-bastion-${each.key}"
  resource_group_name = local.nsg_rg[each.value.rg]
  location            = var.location
  tags                = local.tags
}

resource "azurerm_network_security_rule" "this" {
  for_each = local.nsg_rule_list

  name                        = each.value.name
  resource_group_name         = local.nsg_rg[local.nsg_rules[each.value.nsg].rg]
  network_security_group_name = azurerm_network_security_group.this[each.value.nsg].name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_address_prefix       = each.value.src
  source_port_range           = "*"
  destination_address_prefix  = each.value.dst
  destination_port_range      = each.value.port
}
