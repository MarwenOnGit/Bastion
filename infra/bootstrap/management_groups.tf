# ---------------------------------------------------------------------------
# Management group hierarchy, for structure and documentation:
#
#   Tenant Root Group
#   └── bastion
#       ├── bastion-platform
#       ├── bastion-landing-zones
#       └── bastion-sandbox
#
# Created here, not in CI: the creator of a management group becomes its Owner, and
# no CI identity should own anything.
#
# The subscription stays where it is (under the Tenant Root Group) unless you set
# move_subscription_to_management_group. Moving it is a separate, deliberate step:
# see docs/adr/0001-resource-groups-instead-of-subscriptions.md.
# ---------------------------------------------------------------------------

resource "azurerm_management_group" "bastion" {
  name         = "bastion"
  display_name = "Bastion"
}

resource "azurerm_management_group" "child" {
  for_each = {
    platform        = "Bastion Platform"
    "landing-zones" = "Bastion Landing Zones"
    sandbox         = "Bastion Sandbox"
  }

  name                       = "bastion-${each.key}"
  display_name               = each.value
  parent_management_group_id = azurerm_management_group.bastion.id
}

resource "azurerm_management_group_subscription_association" "move" {
  count = var.move_subscription_to_management_group == "" ? 0 : 1

  management_group_id = azurerm_management_group.child[var.move_subscription_to_management_group].id
  subscription_id     = local.subscription_scope
}
