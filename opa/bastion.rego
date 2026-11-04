# Bastion plan guardrails, run with conftest against `terraform show -json` output.
#
# These cover what checkov does not: Bastion's own rules about cost, scope and
# privilege. They run in plan.yml and apply.yml before anything is applied, and
# their unit tests (bastion_test.rego) run in ci.yml with `conftest verify`.
package main

import rego.v1

protected_groups := {"huginn-lab-rg", "huginn-sentinel-rg", "huginn-tfstate-rg", "fenrir-lab-prod-rg"}

protected_prefixes := {"ctf-"}

# Paid or internet-facing resource types Bastion never deploys (docs/adr/0007).
forbidden_types := {
	"azurerm_public_ip",
	"azurerm_public_ip_prefix",
	"azurerm_firewall",
	"azurerm_firewall_policy",
	"azurerm_bastion_host",
	"azurerm_virtual_network_gateway",
	"azurerm_vpn_gateway",
	"azurerm_express_route_circuit",
	"azurerm_express_route_gateway",
	"azurerm_network_ddos_protection_plan",
	"azurerm_application_gateway",
	"azurerm_nat_gateway",
}

# Owner, User Access Administrator, Role Based Access Control Administrator.
privileged_role_names := {"Owner", "User Access Administrator", "Role Based Access Control Administrator"}

privileged_role_ids := {
	"8e3af657-a8ff-443c-a75c-2fe8c4bcb635",
	"18d7d88d-d35e-4fb5-a5c3-7773c20a72d9",
	"f58310d9-a9f6-439a-9e8d-f62e7b41a168",
}

audit_effects := {"Audit", "AuditIfNotExists", "Disabled"}

max_private_endpoints := 2

# Resources being created or updated, with their planned values.
changes contains rc if {
	some rc in input.resource_changes
	some action in rc.change.actions
	action in {"create", "update"}
}

is_protected(rg) if rg in protected_groups

is_protected(rg) if {
	some p in protected_prefixes
	startswith(rg, p)
}

rg_from_id(id) := lower(parts[i + 1]) if {
	parts := split(id, "/")
	some i
	lower(parts[i]) == "resourcegroups"
}

# --- cost and exposure -------------------------------------------------------

deny contains msg if {
	some rc in changes
	rc.type in forbidden_types
	msg := sprintf("%s: resource type %s is not allowed in Bastion (cost or public exposure, see docs/adr/0007)", [rc.address, rc.type])
}

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_network_interface"
	some ipc in rc.change.after.ip_configuration
	ipc.public_ip_address_id != null
	msg := sprintf("%s: network interfaces must not have a public IP", [rc.address])
}

deny contains msg if {
	count([rc | some rc in changes; rc.type == "azurerm_private_endpoint"]) > max_private_endpoints
	msg := sprintf("plan creates or updates more than %d private endpoints (cost cap, see docs/COST.md)", [max_private_endpoints])
}

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_security_center_subscription_pricing"
	rc.change.after.tier != "Free"
	msg := sprintf("%s: only the Free Defender for Cloud tier is allowed", [rc.address])
}

# --- data services -----------------------------------------------------------

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_storage_account"
	not rc.change.after.shared_access_key_enabled == false
	msg := sprintf("%s: shared_access_key_enabled must be false", [rc.address])
}

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_storage_account"
	not rc.change.after.public_network_access_enabled == false
	msg := sprintf("%s: public_network_access_enabled must be false", [rc.address])
}

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_key_vault"
	not rc.change.after.public_network_access_enabled == false
	msg := sprintf("%s: public_network_access_enabled must be false", [rc.address])
}

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_key_vault"
	not kv_rbac(rc.change.after)
	msg := sprintf("%s: Key Vault must use RBAC authorisation", [rc.address])
}

kv_rbac(after) if after.enable_rbac_authorization == true

kv_rbac(after) if after.rbac_authorization_enabled == true

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_container_registry"
	not rc.change.after.admin_enabled == false
	msg := sprintf("%s: admin_enabled must be false", [rc.address])
}

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_storage_account"
	not rc.change.after.https_traffic_only_enabled == true
	msg := sprintf("%s: https_traffic_only_enabled must be true", [rc.address])
}

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_storage_account"
	not rc.change.after.min_tls_version == "TLS1_2"
	msg := sprintf("%s: min_tls_version must be TLS1_2", [rc.address])
}

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_storage_account"
	not rc.change.after.allow_nested_items_to_be_public == false
	msg := sprintf("%s: allow_nested_items_to_be_public must be false", [rc.address])
}

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_key_vault"
	not rc.change.after.purge_protection_enabled == true
	msg := sprintf("%s: purge_protection_enabled must be true", [rc.address])
}

# --- network ------------------------------------------------------------------

# A standalone subnet is created before its NSG association, which the subnet_nsg
# control (ALZ Deny-Subnet-Without-Nsg) denies. Subnets are declared inline instead.
deny contains msg if {
	some rc in changes
	rc.type in {"azurerm_subnet", "azurerm_subnet_network_security_group_association"}
	msg := sprintf("%s: declare subnets inline in azurerm_virtual_network with security_group (subnet_nsg control)", [rc.address])
}

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_virtual_network"
	some sn in object.get(rc.change.after, "subnet", [])

	# Terraform leaves values that are unknown until apply (a new NSG's ID) out of
	# `after`, so only an explicit null or empty string counts as "no NSG".
	object.get(sn, "security_group", "(known after apply)") in {null, ""}
	not sn.name in nsg_exempt_subnets
	msg := sprintf("%s: subnet %s has no security_group", [rc.address, sn.name])
}

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_virtual_network"
	some sn in object.get(rc.change.after, "subnet", [])
	not sn.default_outbound_access_enabled == false
	msg := sprintf("%s: subnet %s must set default_outbound_access_enabled = false", [rc.address, sn.name])
}

# Same exclusions as the ALZ policy.
nsg_exempt_subnets := {"GatewaySubnet", "AzureFirewallSubnet", "AzureFirewallManagementSubnet", "RouteServerSubnet"}

management_ports := {"22", "3389", "*"}

internet_sources := {"*", "Internet", "0.0.0.0/0", "Any"}

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_network_security_rule"
	a := rc.change.after
	a.direction == "Inbound"
	a.access == "Allow"
	a.source_address_prefix in internet_sources
	a.destination_port_range in management_ports
	msg := sprintf("%s: inbound %s from the internet is not allowed (mgmt_ports_internet control)", [rc.address, a.destination_port_range])
}

# --- privilege ----------------------------------------------------------------

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_role_assignment"
	rc.change.after.role_definition_name in privileged_role_names
	msg := sprintf("%s: assigning %s is not allowed from CI", [rc.address, rc.change.after.role_definition_name])
}

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_role_assignment"
	some rid in privileged_role_ids
	endswith(lower(object.get(rc.change.after, "role_definition_id", "")), rid)
	msg := sprintf("%s: assigning a privileged role (%s) is not allowed from CI", [rc.address, rid])
}

# --- scope safety -------------------------------------------------------------

deny contains msg if {
	some rc in changes
	rg := object.get(rc.change.after, "resource_group_name", "")
	is_protected(rg)
	msg := sprintf("%s: %s is a protected resource group; Bastion never changes it", [rc.address, rg])
}

deny contains msg if {
	some rc in changes
	rc.type == "azurerm_resource_group_policy_assignment"
	rg := rg_from_id(rc.change.after.resource_group_id)
	not startswith(rg, "bastion-")
	msg := sprintf("%s: bastion-baseline may only be assigned to bastion-* resource groups, not %s", [rc.address, rg])
}

wide_assignment_types := {"azurerm_subscription_policy_assignment", "azurerm_management_group_policy_assignment"}

deny contains msg if {
	some rc in changes
	rc.type in wide_assignment_types
	params := json.unmarshal(rc.change.after.parameters)
	some name, p in params
	startswith(name, "effect")
	not p.value in audit_effects
	msg := sprintf("%s: %s = %s; subscription and management group assignments must be audit-only", [rc.address, name, p.value])
}

deny contains msg if {
	some rc in changes
	rc.type in wide_assignment_types
	excluded := {rg_from_id(s) | some s in object.get(rc.change.after, "not_scopes", [])}
	some rg in protected_groups
	not rg in excluded
	msg := sprintf("%s: not_scopes must exclude protected group %s", [rc.address, rg])
}
