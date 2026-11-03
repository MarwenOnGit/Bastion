# ---------------------------------------------------------------------------
# Private DNS zones for the two private endpoints (blob, vault). They sit in the
# hub, as shared services, and are linked to both VNets.
# ---------------------------------------------------------------------------

locals {
  private_dns_zones = {
    blob  = "privatelink.blob.core.windows.net"
    vault = "privatelink.vaultcore.azure.net"
  }

  vnets = {
    hub   = azurerm_virtual_network.hub.id
    spoke = azurerm_virtual_network.spoke.id
  }

  zone_links = merge([
    for zk, zone in local.private_dns_zones : {
      for vk, vnet in local.vnets : "${zk}-${vk}" => { zone = zk, vnet_key = vk, vnet_id = vnet }
    }
  ]...)
}

resource "azurerm_private_dns_zone" "this" {
  for_each = local.private_dns_zones

  name                = each.value
  resource_group_name = data.azurerm_resource_group.hub.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.zone_links

  name                  = "link-${each.value.vnet_key}"
  resource_group_name   = data.azurerm_resource_group.hub.name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.value.zone].name
  virtual_network_id    = each.value.vnet_id
  registration_enabled  = false
  tags                  = local.tags
}
