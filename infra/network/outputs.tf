output "hub_vnet_id" {
  description = "Hub VNet ID."
  value       = azurerm_virtual_network.hub.id
}

output "spoke_vnet_id" {
  description = "Spoke VNet ID."
  value       = azurerm_virtual_network.spoke.id
}

output "private_endpoint_subnet_id" {
  description = "Subnet for the workload's private endpoints."
  value       = local.subnet_ids["spoke-private-endpoints"]
}

output "private_dns_zone_ids" {
  description = "Private DNS zone IDs by short name."
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}

output "reserved_hub_ranges" {
  description = "Hub ranges kept free for a production firewall, gateway and Azure Bastion service. Nothing is deployed there."
  value       = local.reserved_hub_ranges
}

output "subnet_ids" {
  description = "Subnet IDs by <vnet>-<subnet> key."
  value       = local.subnet_ids
}
