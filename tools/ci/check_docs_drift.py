#!/usr/bin/env python3
"""Check that the documentation cannot drift from the repo.

Usage:
  check_docs_drift.py WIKI_DIR [--repo PATH]

WIKI_DIR is a checkout of the project wiki. The check:

1. compares the generated region of CLI-Reference.md against what the
   @cmd headers in the repo produce (tools/ci/gen_cli_reference.py);
2. extracts every `aphotic <command>`, `install.sh --flag`, and
   `tools/devvm/proxmox.sh <subcommand>` quoted in the SDK pages and the
   agent kit guide (fenced blocks and inline code) and fails if any of
   them no longer exists in the repo.

Pages that do not exist yet are skipped, not failed. Exit 0 means the
docs are in sync with this checkout, so a PR to dev checks dev against
the wiki and a release PR to main checks main against it.
"""

import argparse
import difflib
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen_cli_reference as gen  # noqa: E402

# The SDK hub and the pages it links to; the agent kit guide joins this
# list the moment its page exists. Order only affects report order.
SDK_PAGES = [
    "Developer-SDK.md",
    "Dev-VM.md",
    "Contributor-Workflow.md",
    "CLI-Reference.md",
    "Agent-Kit.md",
]

FENCE_RE = re.compile(r"^\s*(```|~~~)")
INLINE_RE = re.compile(r"`([^`\n]+)`")
APHOTIC_RE = re.compile(r"\baphotic\s+([a-z][a-z0-9-]*)")
DEVVM_RE = re.compile(r"\bproxmox\.sh\s+([a-z][a-z0-9-]*)")
INSTALL_FLAG_RE = re.compile(r"--([a-z][a-z-]*)")


def code_regions(text: str) -> list[str]:
    """Fenced code blocks plus inline code spans, as separate regions."""
    regions: list[str] = []
    in_fence = False
    fence_block: list[str] = []
    for line in text.splitlines():
        if FENCE_RE.match(line):
            if in_fence:
                regions.append("\n".join(fence_block))
                fence_block = []
            in_fence = not in_fence
            continue
        if in_fence:
            fence_block.append(line)
        else:
            regions.extend(INLINE_RE.findall(line))
    if fence_block:
        regions.append("\n".join(fence_block))
    return regions


def install_flags(repo: pathlib.Path) -> set[str]:
    """Every long flag install.sh documents or accepts."""
    text = (repo / "install.sh").read_text(encoding="utf-8", errors="replace")
    flags = set()
    for line in text.splitlines():
        m = re.match(r"\s+--([a-z][a-z-]*)", line)
        if m:
            flags.add(m.group(1))
    return flags


def devvm_subcommands(repo: pathlib.Path) -> set[str] | None:
    """The subcommands of tools/devvm/proxmox.sh, from its usage block.

    None when this branch has no devvm tool yet: mentioning a tracked
    tool that a sibling branch adds is branch ordering, not docs drift,
    so the check is skipped rather than failed until it lands.
    """
    path = repo / "tools" / "devvm" / "proxmox.sh"
    if not path.is_file():
        return None
    subcommands = set()
    in_commands = False
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("Commands:"):
            in_commands = True
            continue
        if in_commands:
            m = re.match(r"\s{2}([a-z][a-z0-9-]*)\s{2,}\S", line)
            if m:
                subcommands.add(m.group(1))
            elif line.strip() and not line.startswith("  "):
                in_commands = False
    return subcommands


def check_page(path: pathlib.Path, repo: pathlib.Path, commands: set,
               flags: set, subcommands: set | None) -> list[str]:
    """All drift findings for one wiki page (empty list = in sync)."""
    text = path.read_text(encoding="utf-8", errors="replace")
    findings = []
    for region in code_regions(text):
        for m in APHOTIC_RE.finditer(region):
            if m.group(1) not in commands:
                findings.append(f"`aphotic {m.group(1)}` is not a command in this checkout")
        for line in region.splitlines():
            if "install.sh" not in line:
                continue
            for fm in INSTALL_FLAG_RE.finditer(line):
                if fm.group(1) not in flags:
                    findings.append(f"install.sh does not accept --{fm.group(1)}")
        if subcommands is not None:
            for m in DEVVM_RE.finditer(region):
                if m.group(1) not in subcommands:
                    findings.append(f"tools/devvm/proxmox.sh has no `{m.group(1)}` subcommand")
    return findings


def check_cli_reference(page: pathlib.Path, repo: pathlib.Path) -> list[str]:
    text = page.read_text(encoding="utf-8", errors="replace")
    region = gen.extract_region(text)
    if region is None:
        return [
            "no generated region; run "
            f"`python3 tools/ci/gen_cli_reference.py --update {page.name}`"
        ]
    expected = gen.section_body(gen.render_section(gen.collect_commands(repo)))
    actual = region.strip()
    if actual == expected:
        return []
    diff = "\n".join(
        line for line in difflib.unified_diff(
            expected.splitlines(), actual.splitlines(), "generated", "wiki", lineterm=""
        )
    )
    return ["CLI reference has drifted from the @cmd headers:\n" + diff]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("wiki", help="checkout of the project wiki")
    ap.add_argument("--repo", default=".", help="repo root (default: current dir)")
    args = ap.parse_args()

    repo = pathlib.Path(args.repo).resolve()
    wiki = pathlib.Path(args.wiki).resolve()
    if not wiki.is_dir():
        sys.exit(f"error: {wiki} is not a directory (clone the wiki first)")

    commands = {c["name"] for c in gen.collect_commands(repo)}
    flags = install_flags(repo)
    subcommands = devvm_subcommands(repo)

    failed = False
    checked = 0
    for name in SDK_PAGES:
        page = wiki / name
        if not page.is_file():
            print(f"SKIP {name}: not on the wiki yet")
            continue
        findings: list[str]
        if name == "CLI-Reference.md":
            findings = check_cli_reference(page, repo)
        else:
            findings = check_page(page, repo, commands, flags, subcommands)
        checked += 1
        if findings:
            failed = True
            print(f"FAIL {name}:")
            for f in findings:
                for line in f.splitlines():
                    print(f"  {line}")
        else:
            print(f"PASS {name}: commands, flags, and subcommands are all current")
    if checked == 0:
        print("SKIP no SDK pages on the wiki yet; nothing to check")
    print(f"{'docs drift found' if failed else 'docs in sync'} "
          f"({checked} page{'s' if checked != 1 else ''} checked)")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
