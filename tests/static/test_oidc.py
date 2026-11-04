"""The federated credentials must use ID-based subjects and narrow contexts."""

import re

from conftest import ROOT

IDENTITIES = (ROOT / "infra" / "bootstrap" / "identities.tf").read_text()
VARIABLES = (ROOT / "infra" / "bootstrap" / "variables.tf").read_text()


def default_of(var):
    block = VARIABLES.split(f'variable "{var}"', 1)[1].split("\n}\n", 1)[0]
    return re.search(r'default\s*=\s*"([^"]*)"', block).group(1)


def test_subject_prefix_is_id_based():
    assert (
        'subject_prefix  = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"'
        in IDENTITIES
    )


def test_ids_are_numeric():
    assert default_of("github_owner_id") == "183097322"
    assert re.fullmatch(r"\d+", default_of("github_repo_id"))


def test_subject_contexts_are_narrow():
    contexts = re.findall(r'\$\{local\.subject_prefix\}:([^"]+)"', IDENTITIES)
    assert contexts
    allowed = {"ref:refs/heads/${b}", "pull_request", "environment:bastion-apply", "environment:bastion-policy-tests"}
    assert set(contexts) <= allowed, contexts
    assert "*" not in "".join(contexts)


def test_apply_and_tester_only_trust_their_environment():
    apply = IDENTITIES.split("apply = {", 1)[1].split("}\n    }", 1)[0]
    tester = IDENTITIES.split("policy_tester = {", 1)[1].split("}\n    }", 1)[0]
    assert ":environment:bastion-apply" in apply and "refs/heads" not in apply
    assert ":environment:bastion-policy-tests" in tester and "refs/heads" not in tester


def test_issuer_and_audience():
    assert '"https://token.actions.githubusercontent.com"' in IDENTITIES
    assert '"api://AzureADTokenExchange"' in IDENTITIES
