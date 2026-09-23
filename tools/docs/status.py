#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

from _common import docs_path, repository_root


START = "<!-- generated:in-flight:start -->"
END = "<!-- generated:in-flight:end -->"


def run(args: list[str], root: Path) -> str:
    result = subprocess.run(args, cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f"command failed: {' '.join(args)}")
    return result.stdout


def generated_block(root: Path) -> str:
    gh = shutil.which("gh")
    if not gh:
        raise RuntimeError("gh is not installed")
    pulls = json.loads(
        run(
            [gh, "pr", "list", "--state", "open", "--json", "number,title,headRefName,baseRefName,isDraft,updatedAt"],
            root,
        )
    )
    # Best effort: an offline machine still gets the last-known list.
    subprocess.run(["git", "fetch", "-q", "origin", "main"], cwd=root, timeout=20,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    log = run(["git", "log", "origin/main", "-15", "--oneline"], root).splitlines()
    lines = [START, "", "### Open pull requests", ""]
    if pulls:
        for pull in sorted(pulls, key=lambda item: item["number"]):
            draft = " [draft]" if pull.get("isDraft") else ""
            lines.append(
                f"- PR #{pull['number']}{draft}: {pull['title']} (`{pull['headRefName']}` → `{pull['baseRefName']}`, updated {pull['updatedAt'][:10]})"
            )
    else:
        lines.append("- None.")
    lines.extend(["", "### Recent origin/main", ""])
    lines.extend(f"- `{entry}`" for entry in log)
    lines.extend(["", END])
    return "\n".join(lines)


def replace_block(text: str, block: str) -> str:
    if START in text or END in text:
        if text.count(START) != 1 or text.count(END) != 1 or text.index(START) > text.index(END):
            raise ValueError("STATUS.md has invalid generated markers")
        before, rest = text.split(START, 1)
        _, after = rest.split(END, 1)
        return before.rstrip() + "\n\n" + block + after
    lines = text.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if line.strip().casefold() == "## in flight":
            insertion = index + 1
            prefix = "".join(lines[:insertion]).rstrip()
            suffix = "".join(lines[insertion:]).lstrip("\r\n")
            return prefix + "\n\n" + block + "\n\n" + suffix
    raise ValueError("STATUS.md has no ## In flight heading")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate the current in-flight status block")
    parser.add_argument("--docs")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    docs = docs_path(args.docs)
    try:
        block = generated_block(repository_root())
        if args.write:
            target = docs / "STATUS.md"
            target.write_text(replace_block(target.read_text(encoding="utf-8"), block), encoding="utf-8")
        else:
            print(block)
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"status: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

