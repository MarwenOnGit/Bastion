"""Workflow hygiene: pinned actions, no default permissions, OIDC only where needed, no secrets."""

import re

import pytest
import yaml

from conftest import ROOT

WORKFLOWS = sorted((ROOT / ".github" / "workflows").glob("*.yml"))
EXPECTED = {"ci.yml", "plan.yml", "apply.yml", "drift.yml", "policy-tests.yml"}


def load(p):
    data = yaml.safe_load(p.read_text())
    # PyYAML reads the bare key `on` as True.
    if True in data:
        data["on"] = data.pop(True)
    return data


def test_expected_workflows_exist():
    assert {p.name for p in WORKFLOWS} == EXPECTED


@pytest.mark.parametrize("wf", WORKFLOWS, ids=lambda p: p.name)
def test_top_level_permissions_empty(wf):
    assert load(wf).get("permissions") == {}, f"{wf.name}: top-level permissions must be {{}}"


@pytest.mark.parametrize("wf", WORKFLOWS, ids=lambda p: p.name)
def test_actions_pinned_to_sha(wf):
    for line in wf.read_text().splitlines():
        m = re.search(r"uses:\s*([^\s#]+)", line)
        if m and not m.group(1).startswith("./"):
            assert re.search(r"@[0-9a-f]{40}$", m.group(1)), f"{wf.name}: not pinned to a SHA: {m.group(1)}"


def logs_in_to_azure(job):
    steps = job.get("steps", [])
    env = {**job.get("env", {}), **{k: v for s in steps for k, v in (s.get("env") or {}).items()}}
    return env.get("ARM_USE_OIDC") == "true" or any("azure/login" in (s.get("uses") or "") for s in steps)


@pytest.mark.parametrize("wf", WORKFLOWS, ids=lambda p: p.name)
def test_id_token_only_on_azure_jobs(wf):
    for name, job in load(wf)["jobs"].items():
        perms = job.get("permissions", {}) or {}
        if perms.get("id-token") == "write":
            assert logs_in_to_azure(job), f"{wf.name}/{name}: id-token write but no Azure login"
        if logs_in_to_azure(job):
            assert perms.get("id-token") == "write", f"{wf.name}/{name}: logs in to Azure without id-token write"


# The only secret allowed is the budget alert address: personal data, not a credential.
# Variables render unmasked in logs (GitHub Docs, "Variables"); secrets are redacted.
ALLOWED_SECRETS = {"BUDGET_ALERT_EMAIL"}


@pytest.mark.parametrize("wf", WORKFLOWS, ids=lambda p: p.name)
def test_no_credential_secrets_used(wf):
    text = wf.read_text()
    used = set(re.findall(r"secrets\.([A-Za-z0-9_]+)", text)) - {"GITHUB_TOKEN"}
    assert used <= ALLOWED_SECRETS, f"{wf.name}: uses secrets {used - ALLOWED_SECRETS}; Azure auth is OIDC only"
    assert "client-secret" not in text and "ARM_CLIENT_SECRET" not in text


@pytest.mark.parametrize("wf", WORKFLOWS, ids=lambda p: p.name)
def test_budget_email_never_printed(wf):
    """The address only reaches the one step that builds TF_VAR_budget_alert_emails,
    from a secret, never from a variable, never in job-level env."""
    text = wf.read_text()
    assert "vars.BUDGET_ALERT_EMAIL" not in text
    for name, job in load(wf)["jobs"].items():
        assert "BUDGET_ALERT_EMAIL" not in (job.get("env") or {}), f"{wf.name}/{name}: job-level env is printed in every step"
        for step in job.get("steps", []):
            if "BUDGET_ALERT_EMAIL" in str(step.get("env") or {}):
                assert step["name"] == "Budget email for the governance stack"
                assert "::add-mask::" in step["run"]


def test_budget_email_is_sensitive_in_terraform():
    v = (ROOT / "infra" / "governance" / "variables.tf").read_text()
    block = v.split('variable "budget_alert_emails"', 1)[1].split("validation", 1)[0]
    assert "sensitive   = true" in block


def test_ci_has_no_azure_access():
    ci = load(ROOT / ".github" / "workflows" / "ci.yml")
    for name, job in ci["jobs"].items():
        assert (job.get("permissions") or {}).get("id-token") is None, name
        assert not logs_in_to_azure(job), name


def test_apply_is_manual_and_gated():
    apply = load(ROOT / ".github" / "workflows" / "apply.yml")
    assert set(apply["on"]) == {"workflow_dispatch"}
    for name, job in apply["jobs"].items():
        if logs_in_to_azure(job):
            assert job.get("environment") in ("bastion-apply", {"name": "bastion-apply"}), name
            assert "AZURE_APPLY_CLIENT_ID" in str(job), name


def test_policy_tests_are_gated():
    wf = load(ROOT / ".github" / "workflows" / "policy-tests.yml")
    assert set(wf["on"]) <= {"workflow_dispatch", "schedule"}
    for name, job in wf["jobs"].items():
        if logs_in_to_azure(job):
            assert job.get("environment") in ("bastion-policy-tests", {"name": "bastion-policy-tests"}), name
            assert "AZURE_TESTER_CLIENT_ID" in str(job), name


@pytest.mark.parametrize("name", ["plan.yml", "drift.yml"])
def test_plan_and_drift_use_read_only_identity(name):
    text = (ROOT / ".github" / "workflows" / name).read_text()
    assert "AZURE_PLAN_CLIENT_ID" in text
    assert "AZURE_APPLY_CLIENT_ID" not in text
    assert "-lock=false" in text
    assert "terraform apply" not in text
