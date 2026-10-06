"""tests/test_docs_drift.py

The docs drift machinery (tools/ci/gen_cli_reference.py,
tools/ci/check_docs_drift.py). The repo side is exercised in full here;
the wiki side is exercised against synthetic pages, because a real wiki
checkout needs network (the docs-drift workflow and the weekly wiki sync
run the same checker against the live wiki).
"""

import pathlib
import pytest
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
GEN = REPO / "tools" / "ci" / "gen_cli_reference.py"
CHECK = REPO / "tools" / "ci" / "check_docs_drift.py"


def run(tool: pathlib.Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(tool), *map(str, args)],
        cwd=REPO, capture_output=True, text=True,
    )


def generated_section() -> str:
    out = run(GEN, "--repo", REPO)
    assert out.returncode == 0, out.stderr
    return out.stdout


def write_cli_reference(wiki: pathlib.Path, section: str | None = None) -> None:
    if section is None:
        section = generated_section()
    (wiki / "CLI-Reference.md").write_text(
        "# CLI Reference\n\n> The ground truth is `aphotic --help`.\n\n"
        + section + "\n## Extending\n\nCopy an existing `cmd_*.sh`.\n",
        encoding="utf-8",
    )


def make_wiki(tmp_path: pathlib.Path, pages: dict[str, str]) -> pathlib.Path:
    wiki = tmp_path / "wiki"
    wiki.mkdir()
    for name, body in pages.items():
        (wiki / name).write_text(body, encoding="utf-8")
    return wiki


def check(wiki: pathlib.Path) -> subprocess.CompletedProcess:
    return run(CHECK, wiki, "--repo", REPO)


def test_every_command_file_reaches_the_reference() -> None:
    section = generated_section()
    commands_dir = REPO / "Configs" / ".local" / "lib" / "aphotic" / "commands"
    for path in sorted(commands_dir.glob("cmd_*.sh")):
        m = re.search(r"^#\s*@cmd:\s*(\S+)", path.read_text(), re.M)
        assert m, f"{path.name} has no @cmd header"
        assert f"`aphotic {m.group(1)}`" in section, f"{path.name} missing from the reference"


def test_reference_groups_come_from_headers() -> None:
    section = generated_section()
    groups = set(re.findall(r"^## (.+)$", section, re.M))
    assert "Core" in groups and "Config" in groups and "AI" in groups
    assert "Lifecycle" in groups


def test_check_passes_on_a_consistent_wiki(tmp_path: pathlib.Path) -> None:
    wiki = make_wiki(tmp_path, {
        "Developer-SDK.md": (
            "# Developer SDK\n\n"
            "```bash\naphotic doctor\n"
            "install.sh --channel edge --profile full --no-assistant\n"
            "tools/devvm/proxmox.sh create-vm\n"
            "```\n\nRun `proxmox.sh reset` after a failed test.\n"
        ),
        "Contributor-Workflow.md": (
            "# Contributor Workflow\n\nDrive stable daily; test in the VM:\n\n"
            "```bash\naphotic sync --check\n./install.sh --config-only\n"
            "```\n"
        ),
    })
    write_cli_reference(wiki)
    out = check(wiki)
    assert out.returncode == 0, out.stdout + out.stderr
    assert "docs in sync" in out.stdout


def test_check_fails_when_a_command_is_removed(tmp_path: pathlib.Path) -> None:
    wiki = make_wiki(tmp_path, {
        "Developer-SDK.md": "# SDK\n\n```bash\naphotic frobnicate\n```",
    })
    write_cli_reference(wiki)
    out = check(wiki)
    assert out.returncode == 1
    assert "aphotic frobnicate" in out.stdout


def test_check_fails_when_an_install_flag_is_removed(tmp_path: pathlib.Path) -> None:
    wiki = make_wiki(tmp_path, {
        "Developer-SDK.md": "# SDK\n\n`install.sh --definitely-not-a-flag`",
    })
    write_cli_reference(wiki)
    out = check(wiki)
    assert out.returncode == 1
    assert "--definitely-not-a-flag" in out.stdout


@pytest.mark.skipif(
    not (REPO / "tools" / "devvm" / "proxmox.sh").is_file(),
    reason="this branch has no devvm tool (lands with 12QRFSX)",
)
def test_check_fails_when_a_devvm_subcommand_is_removed(tmp_path: pathlib.Path) -> None:
    wiki = make_wiki(tmp_path, {
        "Dev-VM.md": "# Dev VM\n\n`tools/devvm/proxmox.sh recreate`",
    })
    write_cli_reference(wiki)
    out = check(wiki)
    assert out.returncode == 1
    assert "recreate" in out.stdout


def test_check_fails_on_a_stale_generated_region(tmp_path: pathlib.Path) -> None:
    wiki = make_wiki(tmp_path, {})
    write_cli_reference(wiki)
    page = wiki / "CLI-Reference.md"
    text = page.read_text(encoding="utf-8")
    # Simulate a command being added to the repo without regenerating:
    # the region must no longer match.
    marker = "<!-- aphotic:cli-reference:end -->"
    assert marker in text
    text = text.replace(marker, "- `aphotic a-future-command` -- added to the repo\n" + marker, 1)
    page.write_text(text, encoding="utf-8")
    out = check(wiki)
    assert out.returncode == 1
    assert "drifted" in out.stdout


def test_missing_pages_are_skipped_not_failed(tmp_path: pathlib.Path) -> None:
    out = check(make_wiki(tmp_path, {}))
    assert out.returncode == 0, out.stdout + out.stderr
    assert "nothing to check" in out.stdout
