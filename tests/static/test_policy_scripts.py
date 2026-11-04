"""Run every tests/policy script against a fake `az` to prove the pass/fail logic.

Three fake Azure answers:
  deny-ours   RequestDisallowedByPolicy (or, for DenyAction, a 403 on DELETE) naming
              bastion-baseline and the right reference                              -> test passes
  deny-other  RequestDisallowedByPolicy from some other assignment                      -> test fails
  accept      the PUT succeeds                                                         -> test fails AND
                                                                                         the trap sends DELETE
"""

import os
import pathlib
import stat
import subprocess

import pytest

from conftest import ROOT

SCRIPTS = sorted((ROOT / "tests" / "policy").glob("test-*.sh"))

FAKE_AZ = r"""#!/usr/bin/env bash
# Fake az for offline tests. Logs every call.
echo "$*" >> "$FAKE_AZ_LOG"
url=""
for ((i = 1; i <= $#; i++)); do
  if [[ "${!i}" == "--url" ]]; then j=$((i + 1)); url="${!j}"; fi
done
case "$1 $2" in
  "rest --method")
    method="$3"
    # DenyAction tests: the PUT of the protected canary is allowed; the DELETE is judged.
    if [[ "$url" == *"id-bastion-canary"* ]]; then
      if [[ "$method" == "put" ]]; then echo '{"id": "canary"}'; exit 0; fi
      if [[ "$method" == "delete" ]]; then
        case "$FAKE_AZ_MODE" in
          deny-ours) echo "ERROR: Forbidden (403). The action 'delete' was denied by policy assignment bastion-baseline ($FAKE_AZ_REF)" >&2; exit 1 ;;
          deny-other) echo "ERROR: Forbidden (403). Denied by policy assignment some-other-assignment" >&2; exit 1 ;;
          accept) exit 0 ;;
        esac
      fi
    fi
    if [[ "$method" == "put" ]]; then
      case "$FAKE_AZ_MODE" in
        deny-ours)
          echo "ERROR: (RequestDisallowedByPolicy) Resource was disallowed by policy. {\"policyAssignmentName\":\"bastion-baseline\",\"policyDefinitionReferenceId\":\"$FAKE_AZ_REF\"}" >&2
          exit 1 ;;
        deny-other)
          echo "ERROR: (RequestDisallowedByPolicy) Resource was disallowed by policy. {\"policyAssignmentName\":\"some-other-assignment\",\"policyDefinitionReferenceId\":\"something-else\"}" >&2
          exit 1 ;;
        accept)
          echo '{"id": "created"}'
          exit 0 ;;
      esac
    fi
    exit 0 ;;
  "account show")
    echo "00000000-0000-0000-0000-000000000000"; exit 0 ;;
esac
exit 0
"""


@pytest.fixture()
def fake_az(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    az = bindir / "az"
    az.write_text(FAKE_AZ)
    az.chmod(az.stat().st_mode | stat.S_IEXEC)
    sleep = bindir / "sleep"
    sleep.write_text("#!/usr/bin/env bash\nexit 0\n")
    sleep.chmod(sleep.stat().st_mode | stat.S_IEXEC)
    return bindir, tmp_path / "az.log"


def run(script, bindir, log, mode, ref):
    env = {
        **os.environ,
        "PATH": f"{bindir}:{os.environ['PATH']}",
        "FAKE_AZ_MODE": mode,
        "FAKE_AZ_REF": ref,
        "FAKE_AZ_LOG": str(log),
        "AZURE_SUBSCRIPTION_ID": "00000000-0000-0000-0000-000000000000",
        "AZURE_TENANT_ID": "00000000-0000-0000-0000-000000000000",
    }
    env.pop("GITHUB_STEP_SUMMARY", None)
    return subprocess.run(["bash", str(script)], env=env, capture_output=True, text=True, timeout=60)


def reference_of(script):
    for line in script.read_text().splitlines():
        if line.startswith("# reference: "):
            return line.removeprefix("# reference: ").strip()
    raise AssertionError(f"{script.name}: no reference header")


@pytest.mark.parametrize("script", SCRIPTS, ids=lambda p: p.name)
def test_passes_only_on_our_policy_denial(script, fake_az):
    bindir, log = fake_az
    r = run(script, bindir, log, "deny-ours", reference_of(script))
    assert r.returncode == 0, r.stderr


@pytest.mark.parametrize("script", SCRIPTS, ids=lambda p: p.name)
def test_fails_on_other_policy_denial(script, fake_az):
    bindir, log = fake_az
    r = run(script, bindir, log, "deny-other", reference_of(script))
    assert r.returncode != 0


@pytest.mark.parametrize("script", SCRIPTS, ids=lambda p: p.name)
def test_fails_and_deletes_when_created(script, fake_az):
    bindir, log = fake_az
    r = run(script, bindir, log, "accept", reference_of(script))
    assert r.returncode != 0
    calls = log.read_text()
    assert "--method put" in calls
    assert "--method delete" in calls, "trap did not delete the unexpectedly created resource"
    assert "/resourceGroups/bastion-test-rg/" in calls


@pytest.mark.parametrize("script", SCRIPTS, ids=lambda p: p.name)
def test_only_targets_test_resource_group(script, fake_az):
    bindir, log = fake_az
    run(script, bindir, log, "deny-ours", reference_of(script))
    for line in log.read_text().splitlines():
        if "--url" in line:
            assert "/resourceGroups/bastion-test-rg/" in line, line


def test_cleanup_refuses_other_groups(fake_az):
    bindir, log = fake_az
    r = subprocess.run(
        ["bash", str(ROOT / "tests" / "policy" / "cleanup.sh"), "huginn-lab-rg"],
        env={**os.environ, "PATH": f"{bindir}:{os.environ['PATH']}", "FAKE_AZ_LOG": str(log)},
        capture_output=True,
        text=True,
    )
    assert r.returncode == 2
    assert "refusing" in r.stderr
    assert not pathlib.Path(log).exists() or "delete" not in log.read_text()


FAKE_AZ_POLICY_STATE = r"""#!/usr/bin/env bash
echo "$*" >> "$FAKE_AZ_LOG"
case "$1 $2 $3" in
  "policy state summarize")
    echo '{"policyAssignments":[{"policyDefinitions":[
      {"policyDefinitionReferenceId":"storage-shared-key","results":{"nonCompliantResources":2}},
      {"policyDefinitionReferenceId":"subnet-nsg","results":{"nonCompliantResources":0}}]}]}' ;;
  "policy state list")
    echo '[{"ref":"storage-shared-key","id":"/subscriptions/x/resourceGroups/bastion-test-rg/providers/Microsoft.Storage/storageAccounts/stdemo"}]' ;;
esac
"""


def test_compliance_report_renders_markdown(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    az = bindir / "az"
    az.write_text(FAKE_AZ_POLICY_STATE)
    az.chmod(az.stat().st_mode | stat.S_IEXEC)
    log = tmp_path / "az.log"
    r = subprocess.run(
        ["bash", str(ROOT / "tests" / "policy" / "compliance-report.sh"), "bastion-test-rg"],
        env={**os.environ, "PATH": f"{bindir}:{os.environ['PATH']}", "FAKE_AZ_LOG": str(log)},
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    assert "| `storage-shared-key` | 2 |" in r.stdout
    assert "| `subnet-nsg` | 0 |" in r.stdout
    assert "storageAccounts/stdemo" in r.stdout
    # read-only: no write verbs were called
    assert not any(v in log.read_text() for v in ("trigger-scan", "create", "delete", "put"))


def test_compliance_report_refuses_other_groups(tmp_path):
    r = subprocess.run(
        ["bash", str(ROOT / "tests" / "policy" / "compliance-report.sh"), "fenrir-lab-prod-rg"],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 2
    assert "refusing" in r.stderr
