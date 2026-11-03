"""Checks on policies/initiative.json, policies/effects.json and the custom definitions."""

import json
import re

from conftest import ROOT

GUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
AUDIT_EFFECTS = {"Audit", "AuditIfNotExists", "Disabled"}


def custom_definitions():
    return {
        json.loads(p.read_text())["name"]: json.loads(p.read_text())
        for p in (ROOT / "policies" / "definitions").glob("*.json")
    }


def test_initiative_name(initiative):
    assert initiative["name"] == "bastion-baseline"


def test_reference_ids_unique(initiative):
    refs = [m["referenceId"] for c in initiative["controls"] for m in c["members"]]
    assert len(refs) == len(set(refs)), "duplicate referenceId"


def test_control_names_unique(initiative):
    names = [c["control"] for c in initiative["controls"]]
    assert len(names) == len(set(names))


def test_every_definition_reference_is_valid(initiative):
    customs = custom_definitions()
    for c in initiative["controls"]:
        for m in c["members"]:
            kind, ref = m["definition"].split(":", 1)
            assert kind in {"builtin", "custom"}, m["referenceId"]
            if kind == "builtin":
                assert GUID.match(ref), f"{m['referenceId']}: not a GUID: {ref}"
            else:
                assert ref in customs, f"{m['referenceId']}: no policies/definitions file for {ref}"


def test_member_effect_parameter_matches_control(initiative):
    for c in initiative["controls"]:
        for m in c["members"]:
            assert m["parameters"]["effect"] == f"[parameters('effect_{c['control']}')]", m["referenceId"]


def test_target_and_audit_effects_are_allowed(initiative):
    for c in initiative["controls"]:
        assert c["auditEffect"] in c["allowedEffects"], c["control"]
        assert c["targetEffect"] in c["allowedEffects"], c["control"]
        assert c["auditEffect"] in AUDIT_EFFECTS, c["control"]


def test_effects_file_covers_every_control(initiative, effects):
    controls = {c["control"]: c for c in initiative["controls"]}
    assert set(effects) == set(controls), "effects.json and initiative.json disagree on controls"
    for name, effect in effects.items():
        assert effect in controls[name]["allowedEffects"], f"{name}: {effect} not allowed"


def test_custom_definitions_start_in_audit():
    for name, d in custom_definitions().items():
        eff = d["properties"]["parameters"]["effect"]
        assert eff["defaultValue"] == "Audit", name
        assert "Audit" in eff["allowedValues"], name
        assert d["properties"]["policyRule"]["then"]["effect"] == "[parameters('effect')]", name


def test_every_deny_target_has_a_policy_test(initiative):
    scripts = list((ROOT / "tests" / "policy").glob("test-*.sh"))
    tested = set()
    for s in scripts:
        for line in s.read_text().splitlines():
            if line.startswith("# control: "):
                tested.add(line.removeprefix("# control: ").strip())
    for c in initiative["controls"]:
        if c["targetEffect"] == "Deny":
            assert c["control"] in tested, f"{c['control']} targets Deny but has no tests/policy script"


def test_policy_test_reference_ids_exist(initiative):
    refs = {m["referenceId"] for c in initiative["controls"] for m in c["members"]}
    for s in (ROOT / "tests" / "policy").glob("test-*.sh"):
        ref_lines = [l for l in s.read_text().splitlines() if l.startswith("# reference: ")]
        assert ref_lines, f"{s.name} has no '# reference:' header"
        ref = ref_lines[0].removeprefix("# reference: ").strip()
        assert ref in refs, f"{s.name}: unknown reference {ref}"
        assert f'"{ref}"' in s.read_text(), f"{s.name}: expect_denied does not check {ref}"


def test_docs_list_every_control(initiative):
    text = (ROOT / "docs" / "POLICIES.md").read_text()
    for c in initiative["controls"]:
        assert c["control"] in text, f"docs/POLICIES.md does not mention {c['control']}"
        for m in c["members"]:
            ref = m["definition"].split(":", 1)[1]
            assert ref in text, f"docs/POLICIES.md does not list {ref}"
