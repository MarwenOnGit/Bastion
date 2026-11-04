"""Text-level checks on the Terraform. Complements checkov and conftest; needs no provider download."""

import re

import pytest

from conftest import CI_STACKS, PROTECTED_GROUPS, ROOT, STACKS, tf_files, tf_text

FORBIDDEN_TYPES = [
    "azurerm_public_ip",
    "azurerm_public_ip_prefix",
    "azurerm_firewall",
    "azurerm_bastion_host",
    "azurerm_virtual_network_gateway",
    "azurerm_vpn_gateway",
    "azurerm_express_route_circuit",
    "azurerm_express_route_gateway",
    "azurerm_network_ddos_protection_plan",
    "azurerm_application_gateway",
    "azurerm_nat_gateway",
]

SECRET_RESOURCES = [
    "azuread_application_password",
    "azuread_service_principal_password",
    "azuread_application_certificate",
    "azuread_service_principal_certificate",
]


def resource_blocks(text, rtype):
    """Return the bodies of every `resource "<rtype>" "<name>" { ... }` block."""
    blocks = []
    for m in re.finditer(rf'resource\s+"{rtype}"\s+"[^"]+"\s*\{{', text):
        depth, i = 1, m.end()
        while depth and i < len(text):
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        blocks.append(text[m.end() : i])
    return blocks


@pytest.mark.parametrize("stack", STACKS)
def test_stack_exists(stack):
    assert tf_files(stack), f"infra/{stack} has no .tf files"


@pytest.mark.parametrize("rtype", FORBIDDEN_TYPES)
def test_no_forbidden_resource_types(rtype):
    assert not re.search(rf'resource\s+"{rtype}"', tf_text()), f"{rtype} must not be deployed"


@pytest.mark.parametrize("rtype", SECRET_RESOURCES)
def test_no_credentials_created(rtype):
    assert not re.search(rf'resource\s+"{rtype}"', tf_text()), f"{rtype}: CI uses OIDC only"


def test_no_secret_like_strings():
    text = tf_text()
    for pattern in [r"client_secret\s*=", r"access_key\s*=", r"sas_token\s*=", r"password\s*="]:
        assert not re.search(pattern, text), pattern


def test_at_most_two_private_endpoints():
    assert len(resource_blocks(tf_text(), "azurerm_private_endpoint")) <= 2


def test_every_storage_account_disables_shared_keys():
    blocks = resource_blocks(tf_text(), "azurerm_storage_account")
    assert blocks
    for b in blocks:
        assert re.search(r"shared_access_key_enabled\s*=\s*false", b)
        assert re.search(r'min_tls_version\s*=\s*"TLS1_2"', b)
        assert re.search(r"allow_nested_items_to_be_public\s*=\s*false", b)


def test_workload_data_services_are_private():
    text = tf_text("workload")
    for rtype in ["azurerm_storage_account", "azurerm_key_vault"]:
        for b in resource_blocks(text, rtype):
            assert re.search(r"public_network_access_enabled\s*=\s*false", b), rtype
    for b in resource_blocks(text, "azurerm_key_vault"):
        assert re.search(r"(enable_rbac_authorization|rbac_authorization_enabled)\s*=\s*true", b)


@pytest.mark.parametrize("stack", CI_STACKS)
def test_ci_stacks_use_entra_backend(stack):
    text = tf_text(stack)
    assert 'backend "azurerm"' in text
    assert re.search(r"use_azuread_auth\s*=\s*true", text)
    assert re.search(rf'key\s*=\s*"{stack}\.tfstate"', text)


def test_bootstrap_state_is_local():
    assert 'backend "' not in tf_text("bootstrap")
    gitignore = (ROOT / ".gitignore").read_text()
    assert "infra/bootstrap/terraform.tfstate" in gitignore


def test_no_owner_or_uaa_assignments():
    text = tf_text()
    for role in ["Owner", "User Access Administrator", "Role Based Access Control Administrator"]:
        assert not re.search(rf'role(_definition_name)?\s*=\s*"{role}"', text), role


def test_ci_never_gets_role_assignment_rights():
    roles = re.findall(r'role\s*=\s*"([^"]+)"', tf_text("bootstrap"))
    assert roles
    for r in roles:
        assert r not in {"Owner", "User Access Administrator", "Role Based Access Control Administrator"}


def test_protected_groups_in_governance_defaults():
    text = (ROOT / "infra" / "governance" / "variables.tf").read_text()
    block = text.split('variable "protected_resource_groups"', 1)[1].split("}\n", 1)[0]
    for rg in PROTECTED_GROUPS:
        assert f'"{rg}"' in block, rg


def test_protected_groups_never_targeted():
    """No resource is placed in a protected group; the only reference allowed is the
    Huginn workspace ID (diagnostic target) and the exclusion list."""
    for p in tf_files():
        if p.name == "variables.tf":  # the Huginn workspace reference lives in a variable default
            continue
        for line in p.read_text().splitlines():
            if re.search(r"resource_group_name\s*=", line):
                for rg in PROTECTED_GROUPS:
                    assert rg not in line, f"{p}: {line.strip()}"
                assert '"ctf-' not in line


def test_assignment_groups_are_bastion_groups():
    text = (ROOT / "infra" / "governance" / "variables.tf").read_text()
    block = text.split('variable "assignment_resource_groups"', 1)[1].split("validation", 1)[0]
    groups = re.findall(r'"([a-z0-9-]+-rg)"', block)
    assert groups and all(g.startswith("bastion-") for g in groups)


def test_no_deny_or_dine_at_subscription_scope():
    text = (ROOT / "infra" / "governance" / "policy.tf").read_text()
    sub = resource_blocks(text, "azurerm_subscription_policy_assignment")
    assert len(sub) <= 1
    for b in sub:
        assert "audit_only_parameters" in b
        assert "not_scopes" in b
    assert not resource_blocks(text, "azurerm_management_group_policy_assignment")


def test_no_vm_in_always_on_design():
    for rtype in ["azurerm_linux_virtual_machine", "azurerm_windows_virtual_machine", "azurerm_virtual_machine"]:
        assert not re.search(rf'resource\s+"{rtype}"', tf_text()), rtype


def test_subnets_are_inline_with_an_nsg():
    """subnet_nsg (ALZ Deny-Subnet-Without-Nsg) denies a subnet created before its NSG
    association, so every subnet is declared inside its VNet with security_group set."""
    text = tf_text()
    assert not re.search(r'resource\s+"azurerm_subnet"\s', text)
    assert not re.search(r'resource\s+"azurerm_subnet_network_security_group_association"', text)
    for b in resource_blocks(tf_text("network"), "azurerm_virtual_network"):
        assert "security_group" in b and "default_outbound_access_enabled = false" in b


def test_providers_are_pinned_to_a_minor_version():
    for p in tf_files():
        for m in re.finditer(r'version\s*=\s*"([^"]+)"', p.read_text()):
            v = m.group(1)
            if v.startswith("~>"):
                assert re.fullmatch(r"~> \d+\.\d+", v), f"{p}: {v} (pin at least the minor version)"


# --- review finding 1: CI to law-huginn through id-bastion-policy ----------------

IDENTITY_CARRYING_TYPES = [
    "Microsoft.ContainerInstance/containerGroups",
    "Microsoft.Automation/automationAccounts",
    "Microsoft.Resources/deploymentScripts",
    "Microsoft.App/containerApps",
    "Microsoft.App/jobs",
    "Microsoft.Web/sites",
    "Microsoft.Batch/batchAccounts",
    "Microsoft.Logic/workflows",
]

AZURERM_IDENTITY_CARRYING = [
    "azurerm_container_group",
    "azurerm_automation_account",
    "azurerm_resource_deployment_script_azure_cli",
    "azurerm_resource_deployment_script_azure_power_shell",
    "azurerm_container_app",
    "azurerm_container_app_job",
    "azurerm_linux_web_app",
    "azurerm_windows_web_app",
    "azurerm_linux_function_app",
    "azurerm_windows_function_app",
    "azurerm_batch_account",
    "azurerm_logic_app_workflow",
]


def test_policy_identity_has_its_own_group():
    roles = (ROOT / "infra" / "bootstrap" / "roles.tf").read_text()
    uai = roles.split('resource "azurerm_user_assigned_identity" "policy"', 1)[1].split("\n}\n", 1)[0]
    assert 'azurerm_resource_group.this["identity"].name' in uai
    assert '"bastion-identity-rg"' in (ROOT / "infra" / "bootstrap" / "main.tf").read_text()
    gov = (ROOT / "infra" / "governance" / "variables.tf").read_text()
    assert 'default     = "bastion-identity-rg"' in gov.split('variable "policy_identity_resource_group"', 1)[1]
    assert '"bastion-identity-rg"' in gov.split('variable "assignment_resource_groups"', 1)[1].split("}", 1)[0]


def test_no_ci_identity_has_write_on_identity_group():
    roles = (ROOT / "infra" / "bootstrap" / "roles.tf").read_text()
    ci = roles.split("ci_role_assignments = {", 1)[1].split("\n  }\n", 1)[0]
    assert 'rg_ids["identity"]' not in ci, "no CI role assignment may target bastion-identity-rg"


def test_apply_only_references_the_identity():
    roles = (ROOT / "infra" / "bootstrap" / "roles.tf").read_text()
    role = roles.split('resource "azurerm_role_definition" "policy_identity_reference"', 1)[1].split("\n}\n", 1)[0]
    actions = re.findall(r'"(Microsoft\.[^"]+)"', role)
    assert sorted(actions) == [
        "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",
        "Microsoft.ManagedIdentity/userAssignedIdentities/read",
    ]
    ra = roles.split('resource "azurerm_role_assignment" "apply_policy_identity_reference"', 1)[1].split("\n}\n", 1)[0]
    assert "scope                            = azurerm_user_assigned_identity.policy.id" in ra


def test_huginn_workspace_role_is_narrow_by_default():
    roles = (ROOT / "infra" / "bootstrap" / "roles.tf").read_text()
    role = roles.split('resource "azurerm_role_definition" "diagnostics_destination"', 1)[1].split("\n}\n", 1)[0]
    assert sorted(re.findall(r'"(Microsoft\.[^"]+)"', role)) == [
        "Microsoft.OperationalInsights/workspaces/read",
        "Microsoft.OperationalInsights/workspaces/sharedKeys/action",
    ]
    v = (ROOT / "infra" / "bootstrap" / "variables.tf").read_text()
    assert re.search(r'variable "narrow_huginn_workspace_role" \{[^}]*default     = true', v, re.S)
    assert re.search(r'variable "policy_identity_log_analytics_contributor" \{[^}]*default     = false', v, re.S)


def test_huginn_workspace_is_locked_by_default():
    roles = (ROOT / "infra" / "bootstrap" / "roles.tf").read_text()
    lock = roles.split('resource "azurerm_management_lock" "huginn_workspace"', 1)[1].split("\n}\n", 1)[0]
    assert 'lock_level = "CanNotDelete"' in lock and "local.huginn_workspace_id" in lock
    v = (ROOT / "infra" / "bootstrap" / "variables.tf").read_text()
    assert re.search(r'variable "lock_huginn_workspace" \{[^}]*default     = true', v, re.S)


@pytest.mark.parametrize("rtype", IDENTITY_CARRYING_TYPES)
def test_identity_carrying_compute_is_denied(rtype):
    gov = (ROOT / "infra" / "governance" / "variables.tf").read_text()
    block = gov.split('variable "denied_resource_types"', 1)[1].split("\n}\n", 1)[0]
    assert f'"{rtype}"' in block


@pytest.mark.parametrize("rtype", AZURERM_IDENTITY_CARRYING)
def test_stacks_use_no_identity_carrying_compute(rtype):
    assert not re.search(rf'resource\s+"{rtype}"', tf_text()), f"{rtype} would be denied by denied_resource_types"


def test_denied_types_test_covers_a_container_group():
    script = (ROOT / "tests" / "policy" / "test-denied-resource-types.sh").read_text()
    assert "Microsoft.ContainerInstance/containerGroups" in script
