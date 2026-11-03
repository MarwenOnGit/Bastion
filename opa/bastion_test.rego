package main

import rego.v1

rc(type, after) := rcn(type, "test", after)

rcn(type, name, after) := {"address": sprintf("%s.%s", [type, name]), "type": type, "change": {"actions": ["create"], "after": after}}

plan(changes) := {"resource_changes": changes}

good_storage := {"shared_access_key_enabled": false, "public_network_access_enabled": false, "resource_group_name": "bastion-spoke-app-rg"}

good_kv := {"public_network_access_enabled": false, "enable_rbac_authorization": true, "resource_group_name": "bastion-spoke-app-rg"}

test_compliant_workload_passes if {
	count(deny) == 0 with input as plan([
		rc("azurerm_storage_account", good_storage),
		rc("azurerm_key_vault", good_kv),
		rcn("azurerm_private_endpoint", "blob", {"resource_group_name": "bastion-spoke-app-rg"}),
		rcn("azurerm_private_endpoint", "vault", {"resource_group_name": "bastion-spoke-app-rg"}),
	])
}

test_public_ip_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_public_ip", {"resource_group_name": "bastion-hub-rg"})])
}

test_firewall_and_bastion_host_denied if {
	count(deny) == 2 with input as plan([
		rc("azurerm_firewall", {"resource_group_name": "bastion-hub-rg"}),
		rc("azurerm_bastion_host", {"resource_group_name": "bastion-hub-rg"}),
	])
}

test_nic_with_public_ip_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_network_interface", {
		"resource_group_name": "bastion-spoke-app-rg",
		"ip_configuration": [{"public_ip_address_id": "/subscriptions/x/resourceGroups/bastion-spoke-app-rg/providers/Microsoft.Network/publicIPAddresses/pip"}],
	})])
}

test_nic_without_public_ip_passes if {
	count(deny) == 0 with input as plan([rc("azurerm_network_interface", {
		"resource_group_name": "bastion-spoke-app-rg",
		"ip_configuration": [{"public_ip_address_id": null}],
	})])
}

test_storage_shared_key_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_storage_account", object.union(good_storage, {"shared_access_key_enabled": true}))])
}

test_storage_shared_key_missing_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_storage_account", object.remove(good_storage, ["shared_access_key_enabled"]))])
}

test_storage_public_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_storage_account", object.union(good_storage, {"public_network_access_enabled": true}))])
}

test_kv_access_policies_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_key_vault", object.union(good_kv, {"enable_rbac_authorization": false}))])
}

test_kv_new_rbac_argument_accepted if {
	count(deny) == 0 with input as plan([rc("azurerm_key_vault", {"public_network_access_enabled": false, "rbac_authorization_enabled": true, "resource_group_name": "bastion-spoke-app-rg"})])
}

test_acr_admin_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_container_registry", {"admin_enabled": true, "resource_group_name": "bastion-spoke-app-rg"})])
}

test_three_private_endpoints_denied if {
	count(deny) == 1 with input as plan([
		rcn("azurerm_private_endpoint", "a", {"resource_group_name": "bastion-spoke-app-rg"}),
		rcn("azurerm_private_endpoint", "b", {"resource_group_name": "bastion-spoke-app-rg"}),
		rcn("azurerm_private_endpoint", "c", {"resource_group_name": "bastion-spoke-app-rg"}),
	])
}

test_owner_by_name_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_role_assignment", {"role_definition_name": "Owner", "scope": "/subscriptions/x"})])
}

test_uaa_by_id_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_role_assignment", {"role_definition_id": "/subscriptions/x/providers/Microsoft.Authorization/roleDefinitions/18d7d88d-d35e-4fb5-a5c3-7773c20a72d9", "scope": "/subscriptions/x"})])
}

test_reader_allowed if {
	count(deny) == 0 with input as plan([rc("azurerm_role_assignment", {"role_definition_name": "Reader", "scope": "/subscriptions/x"})])
}

test_protected_group_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_network_security_group", {"resource_group_name": "fenrir-lab-prod-rg"})])
}

test_ctf_group_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_network_security_group", {"resource_group_name": "ctf-web-01"})])
}

test_rg_assignment_outside_bastion_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_resource_group_policy_assignment", {"resource_group_id": "/subscriptions/x/resourceGroups/huginn-lab-rg"})])
}

test_rg_assignment_bastion_allowed if {
	count(deny) == 0 with input as plan([rc("azurerm_resource_group_policy_assignment", {"resource_group_id": "/subscriptions/x/resourceGroups/bastion-test-rg"})])
}

all_excluded := [sprintf("/subscriptions/x/resourceGroups/%s", [g]) | some g in protected_groups]

test_subscription_audit_only_allowed if {
	count(deny) == 0 with input as plan([rc("azurerm_subscription_policy_assignment", {
		"parameters": json.marshal({"effect_storage_shared_key": {"value": "Audit"}, "effect_diagnostic_settings": {"value": "AuditIfNotExists"}, "listOfAllowedLocations": {"value": ["francecentral"]}}),
		"not_scopes": all_excluded,
	})])
}

test_subscription_deny_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_subscription_policy_assignment", {
		"parameters": json.marshal({"effect_storage_shared_key": {"value": "Deny"}}),
		"not_scopes": all_excluded,
	})])
}

test_subscription_missing_exclusion_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_subscription_policy_assignment", {
		"parameters": json.marshal({"effect_storage_shared_key": {"value": "Audit"}}),
		"not_scopes": [s | some s in all_excluded; not contains(s, "fenrir")],
	})])
}

test_paid_defender_denied if {
	count(deny) == 1 with input as plan([rc("azurerm_security_center_subscription_pricing", {"tier": "Standard", "resource_type": "VirtualMachines"})])
}

test_deletes_are_ignored if {
	count(deny) == 0 with input as {"resource_changes": [{"address": "azurerm_public_ip.old", "type": "azurerm_public_ip", "change": {"actions": ["delete"], "after": null}}]}
}
