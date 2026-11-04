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
