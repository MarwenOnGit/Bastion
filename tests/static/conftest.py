import json
import pathlib

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[2]

STACKS = ["bootstrap", "governance", "network", "workload"]
CI_STACKS = ["governance", "network", "workload"]
PROTECTED_GROUPS = {"huginn-lab-rg", "huginn-sentinel-rg", "huginn-tfstate-rg", "fenrir-lab-prod-rg"}


@pytest.fixture(scope="session")
def root():
    return ROOT


@pytest.fixture(scope="session")
def initiative():
    return json.loads((ROOT / "policies" / "initiative.json").read_text())


@pytest.fixture(scope="session")
def effects():
    data = json.loads((ROOT / "policies" / "effects.json").read_text())
    return {k: v for k, v in data.items() if not k.startswith("_")}


def tf_files(stack=None):
    base = ROOT / "infra" / stack if stack else ROOT / "infra"
    return sorted(p for p in base.rglob("*.tf") if ".terraform" not in p.parts)


def tf_text(stack=None):
    return "\n".join(p.read_text() for p in tf_files(stack))
