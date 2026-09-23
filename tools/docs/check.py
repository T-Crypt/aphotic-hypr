#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import socket
import subprocess
from collections import defaultdict
from datetime import date, datetime
from pathlib import Path

from _common import docs_path, markdown_files, repository_root

HISTORY = {"LEDGER.md", "DECISIONS.md", "KNOWLEDGE_BASE.md"}


STATE_WORDS = r"open|opened|draft|merged|closed"
PATH_PREFIXES = ("Configs/", "lib/", "tests/", "tools/", "scripts/", "profiles/", "site/", "src/", "assets/", ".epiq/")


def command(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)


def finding(kind: str, path: str, line: int, claim: str, evidence: str) -> dict[str, object]:
    return {"type": kind, "file": path, "line": line, "claim": claim, "evidence": evidence}


def expected_pr_state(word: str) -> str:
    word = word.casefold()
    if word in {"open", "opened", "draft"}:
        return "OPEN"
    return word.upper()


def repo_file_claim(raw: str, root: Path) -> str | None:
    candidate = raw.strip().rstrip(".,:;)")
    candidate = re.sub(r"::.*$", "", candidate)
    candidate = re.sub(r":\d+(?::\d+)?$", "", candidate)
    if not candidate.startswith(PATH_PREFIXES) or any(char.isspace() for char in candidate):
        return None
    if candidate.endswith("/") or any(char in candidate for char in "*?[]<>{}"):
        return None
    local = root / candidate
    if local.is_dir():
        return None
    name = Path(candidate).name
    if not local.is_file() and "." not in name and not candidate.startswith("Configs/.local/bin/"):
        return None
    return candidate


def scan(args: argparse.Namespace) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    docs = docs_path(args.docs)
    root = repository_root()
    findings: list[dict[str, object]] = []
    skipped: list[dict[str, object]] = []
    pr_cache: dict[int, tuple[str | None, str | None]] = {}
    path_cache: dict[str, tuple[bool, bool]] = {}
    branch_cache: dict[str, bool] = {}
    net_cache: dict[tuple[str, int], str | None] = {}
    gh = shutil.which("gh")
    for document in markdown_files(docs):
        # History records what was true when written; checking it against
        # today only ever reports that time passed.
        if document.relative_to(docs).as_posix() in HISTORY:
            continue
        relative = document.relative_to(docs).as_posix()
        lines = document.read_text(encoding="utf-8", errors="replace").splitlines()
        for number, line in enumerate(lines, 1):
            for match in re.finditer(rf"(?i)(?:\b({STATE_WORDS})\b.{{0,80}}#(\d+)|#(\d+).{{0,80}}\b({STATE_WORDS})\b)", line):
                word = match.group(1) or match.group(4)
                issue = int(match.group(2) or match.group(3))
                if issue not in pr_cache:
                    if not gh:
                        pr_cache[issue] = (None, "gh is not installed")
                    else:
                        result = command([gh, "pr", "view", str(issue), "--json", "state"], root)
                        try:
                            state = json.loads(result.stdout).get("state") if result.returncode == 0 else None
                        except json.JSONDecodeError:
                            state = None
                        error = None if state else (result.stderr.strip() or "gh returned no state")
                        pr_cache[issue] = (state, error)
                state, error = pr_cache[issue]
                if error:
                    skipped.append(finding("pr", relative, number, f"#{issue} {word}", error))
                elif state != expected_pr_state(word):
                    findings.append(finding("pr", relative, number, f"#{issue} {word}", f"reported state is {state}"))
            for raw in re.findall(r"`([^`]+)`", line):
                candidate = repo_file_claim(raw, root)
                if candidate is None:
                    continue
                if candidate not in path_cache:
                    tracked = command(["git", "ls-files", "--error-unmatch", "--", candidate], root).returncode == 0
                    on_origin = command(["git", "cat-file", "-e", f"origin/main:{candidate}"], root).returncode == 0
                    path_cache[candidate] = (tracked, on_origin)
                tracked, on_origin = path_cache[candidate]
                if not tracked or not on_origin:
                    evidence = f"tracked={'yes' if tracked else 'no'}, origin/main={'yes' if on_origin else 'no'}"
                    findings.append(finding("path", relative, number, candidate, evidence))
            for branch in re.findall(r"\b(?:feature|fix)/[A-Za-z0-9._/-]+", line):
                branch = branch.rstrip(".,:;)")
                near_open = re.search(r"(?i)\b(open|opened|draft|in[- ]flight)\b", line)
                if not near_open:
                    continue
                if branch not in branch_cache:
                    branch_cache[branch] = command(
                        ["git", "show-ref", "--verify", "--quiet", f"refs/remotes/origin/{branch}"], root
                    ).returncode == 0
                if not branch_cache[branch]:
                    findings.append(finding("branch", relative, number, branch, "remote branch is absent"))
            if args.net:
                endpoints = [(host, int(port)) for host, port in re.findall(r"\b((?:\d{1,3}\.){3}\d{1,3}|[A-Za-z0-9.-]+):(\d{1,5})\b", line)]
                for host, port in endpoints:
                    key = (host, port)
                    if key not in net_cache:
                        try:
                            with socket.create_connection(key, timeout=1):
                                net_cache[key] = None
                        except OSError as error:
                            net_cache[key] = str(error)
                    if net_cache[key]:
                        findings.append(finding("network", relative, number, f"{host}:{port}", net_cache[key] or "unreachable"))
            if relative == "STATUS.md":
                updated = re.search(r"(?i)Updated:\s*(\d{4}-\d{2}-\d{2})", line)
                if updated:
                    value = datetime.strptime(updated.group(1), "%Y-%m-%d").date()
                    age = (date.today() - value).days
                    if age > 7:
                        findings.append(finding("updated", relative, number, updated.group(1), f"{age} days old"))
    return findings, skipped


def print_human(findings: list[dict[str, object]], skipped: list[dict[str, object]]) -> None:
    grouped = defaultdict(list)
    for item in findings:
        grouped[item["file"]].append(item)
    for path in sorted(grouped):
        print(path)
        for item in grouped[path]:
            print(f"  {item['line']}: STALE [{item['type']}] {item['claim']} ({item['evidence']})")
    if skipped:
        print("Skipped checks")
        for item in skipped:
            print(f"  {item['file']}:{item['line']} [{item['type']}] {item['claim']} ({item['evidence']})")
    if not findings:
        print("No stale claims found.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Check documentation claims against repository state")
    parser.add_argument("--docs")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--net", action="store_true")
    parser.add_argument("--warn-only", action="store_true")
    args = parser.parse_args()
    findings, skipped = scan(args)
    if args.json:
        print(json.dumps({"findings": findings, "skipped": skipped}, sort_keys=True))
    else:
        print_human(findings, skipped)
    return 0 if args.warn_only or not findings else 1


if __name__ == "__main__":
    raise SystemExit(main())
