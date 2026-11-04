"""Documentation checks: required files exist, plain punctuation, relative links resolve."""

import re

import pytest

from conftest import ROOT

REQUIRED = [
    "README.md",
    "docs/ARCHITECTURE.md",
    "docs/PREVENT-DETECT.md",
    "docs/POLICIES.md",
    "docs/SETUP.md",
    "docs/STATUS.md",
    "docs/COST.md",
    "docs/DEMO.md",
]

DOCS = sorted(p for p in ROOT.rglob("*.md") if ".terraform" not in p.parts and ".pytest_cache" not in p.parts)


@pytest.mark.parametrize("path", REQUIRED)
def test_required_doc_exists(path):
    assert (ROOT / path).is_file(), path


def test_at_least_seven_adrs():
    assert len(list((ROOT / "docs" / "adr").glob("[0-9][0-9][0-9][0-9]-*.md"))) >= 7


@pytest.mark.parametrize("doc", DOCS, ids=lambda p: str(p.relative_to(ROOT)))
def test_no_em_dashes(doc):
    assert "—" not in doc.read_text(), f"{doc.relative_to(ROOT)} contains an em dash"


@pytest.mark.parametrize("doc", DOCS, ids=lambda p: str(p.relative_to(ROOT)))
def test_relative_links_resolve(doc):
    for target in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", doc.read_text()):
        if re.match(r"^[a-z]+:", target):
            continue
        assert (doc.parent / target).exists(), f"{doc.relative_to(ROOT)}: broken link {target}"


def test_azure_bastion_name_clarified():
    readme = (ROOT / "README.md").read_text()
    assert "Bastion landing zone" in readme
    assert "does not deploy" in readme and "Azure Bastion" in readme


def test_every_fenrir_operation_mapped():
    text = (ROOT / "docs" / "PREVENT-DETECT.md").read_text()
    ids = (
        [f"A-0{i}" for i in range(1, 6)]
        + [f"E-{i:02d}" for i in range(1, 28)]
        + [f"X-{i:02d}" for i in range(1, 22)]
        + [f"P-{i:02d}" for i in range(1, 14)]
        + ["D-01", "D-02", "D-03"]
    )
    # Ranges such as "E-08 to E-13" count for every ID inside them.
    covered = set(re.findall(r"\b[AEXPD]-\d{2}\b", text))
    for a, b in re.findall(r"\b([AEXPD]-\d{2}) to ([AEXPD]-\d{2})\b", text):
        prefix = a[0]
        covered |= {f"{prefix}-{i:02d}" for i in range(int(a[2:]), int(b[2:]) + 1)}
    missing = [i for i in ids if i not in covered]
    assert not missing, f"PREVENT-DETECT.md does not cover {missing}"
