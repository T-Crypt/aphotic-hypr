#!/usr/bin/env python3
"""Print what a red CI run actually failed on, without the runner noise.

    tools/ci/triage.py 292            a pull request: every check, then the failures
    tools/ci/triage.py 37379451673    one workflow run by id
    tools/ci/triage.py --log run.log  a saved `gh run view --log-failed` dump

Reads finished runs only. It never waits for a run to finish.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys

REPO = "T-Crypt/aphotic-hypr"
# Branch protection on dev and main. Read live when the token allows it.
REQUIRED = ["test", "shellcheck", "bash-syntax", "Analyze (python)", "Analyze (actions)"]
MAX_BLOCK = 40

PREFIX = re.compile(r"^[^\t]*\t[^\t]*\t")
STAMP = re.compile(r"^﻿?\d{4}-\d\d-\d\dT[\d:.]+Z ?")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
RUN_ID = re.compile(r"/actions/runs/(\d+)")


def gh(*args: str) -> str:
    result = subprocess.run(["gh", *args], capture_output=True, text=True, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f"gh {' '.join(args)} failed")
    return result.stdout


def clean(raw: str) -> list[str]:
    """Strip the job/step/timestamp prefix, ANSI codes and runner bookkeeping."""
    lines: list[str] = []
    in_env = False
    for line in raw.splitlines():
        line = ANSI.sub("", STAMP.sub("", PREFIX.sub("", line, count=1)))
        if line.startswith("##[group]") or line.startswith("##[endgroup]"):
            in_env = False
            continue
        if line.startswith("env:") or line.startswith("shell: "):
            in_env = line.startswith("env:")
            continue
        if in_env and line.startswith("  "):
            continue
        in_env = False
        lines.append(line)
    return lines


def failures(lines: list[str]) -> list[tuple[str, list[str]]]:
    """Return (title, lines) for each failure the log shows."""
    found: list[tuple[str, list[str]]] = []
    current, block = None, []
    for line in lines:
        header = re.match(r"^=== (tests/\S+) ===$", line)
        if header:
            current, block = header.group(1), []
            continue
        failed = re.match(r"^FAILED: (tests/\S+)$", line)
        if failed:
            found.append((failed.group(1), block if current == failed.group(1) else []))
            current, block = None, []
            continue
        if current:
            block.append(line)

    for i, line in enumerate(lines):
        if line.startswith("SYNTAX ERROR: "):
            context = [lines[i - 1]] if i and not lines[i - 1].startswith("SYNTAX ERROR") else []
            found.append((line.removeprefix("SYNTAX ERROR: "), context + [line]))

    start = next((i for i, l in enumerate(lines) if re.match(r"^=+ FAILURES =+$", l)), None)
    if start is None:
        start = next((i for i, l in enumerate(lines) if "short test summary info" in l), None)
    if start is not None:
        end = next((i for i in range(start + 1, len(lines))
                    if re.match(r"^=+ .*(passed|failed|error).* =+$", lines[i])), len(lines))
        found.append(("pytest", lines[start:end + 1]))
    return found


def show(lines: list[str]) -> None:
    if len(lines) > MAX_BLOCK:
        print(f"      ... {len(lines) - MAX_BLOCK} earlier lines cut")
        lines = lines[-MAX_BLOCK:]
    for line in lines:
        print(f"      {line}")


def rerun_hint(title: str, block: list[str]) -> str | None:
    if title.startswith("tests/") and title.endswith((".sh", ".py")):
        return f"tools/ci/local.sh --test {title}"
    if title == "pytest":
        files = sorted({m.group(1) for l in block if (m := re.match(r"^(?:FAILED|ERROR) (tests/[^:\s]+\.py)", l))})
        if files:
            return "; ".join(f"tools/ci/local.sh --test {f}" for f in files)
        return "tools/ci/local.sh --only py"
    if title.endswith(".sh") or "aphotic" in title:
        return "tools/ci/local.sh --only syntax"
    return None


def triage_log(raw: str) -> bool:
    lines = clean(raw)
    found = failures(lines)
    if not found:
        tail = [l for l in lines if l.strip() and not l.startswith("##[")][-25:]
        print("  no test failure blocks found; last lines of the failed step:")
        show(tail)
        return False
    for title, block in found:
        print(f"  FAILED {title}")
        show(block)
        hint = rerun_hint(title, block)
        if hint:
            print(f"      reproduce: {hint}")
    return True


def required_checks() -> list[str]:
    try:
        data = json.loads(gh("api", f"repos/{REPO}/branches/dev/protection/required_status_checks"))
        return data.get("contexts") or REQUIRED
    except (RuntimeError, json.JSONDecodeError):
        return REQUIRED


def codeql_alerts(pr: str) -> None:
    try:
        alerts = json.loads(gh("api", f"repos/{REPO}/code-scanning/alerts?ref=refs/pull/{pr}/merge&state=open&per_page=50"))
    except (RuntimeError, json.JSONDecodeError) as err:
        print(f"  could not read code scanning alerts: {err}")
        return
    if not alerts:
        print("  no open code scanning alerts on this pull request")
    for alert in alerts:
        loc = alert.get("most_recent_instance", {}).get("location", {})
        msg = alert.get("most_recent_instance", {}).get("message", {}).get("text", "").splitlines()
        print(f"  ALERT {alert['rule']['id']} {loc.get('path')}:{loc.get('start_line')}  {msg[0] if msg else ''}")


def triage_pr(pr: str) -> int:
    checks = json.loads(gh("pr", "checks", pr, "--json", "name,bucket,link,workflow"))
    required = required_checks()
    red_runs: dict[str, list[str]] = {}
    blocking = 0
    codeql_red = False
    print(f"PR #{pr} checks (required: {', '.join(required)})")
    for check in sorted(checks, key=lambda c: (c["name"] not in required, c["name"])):
        name, bucket = check["name"], check["bucket"]
        is_required = name in required
        if bucket == "fail" and not is_required:
            label = "IGNORE (fail, not required)"
        elif bucket == "fail":
            label = "FAIL"
            blocking += 1
        else:
            label = bucket.upper()
        print(f"  {label:<28} {name}")
        if bucket == "fail" and is_required:
            if name.startswith("Analyze") or name == "CodeQL":
                codeql_red = True
            match = RUN_ID.search(check.get("link") or "")
            if match:
                red_runs.setdefault(match.group(1), []).append(name)
    if any(c["bucket"] == "pending" for c in checks):
        print("Some checks are still running. Run this again once they finish; don't wait on them in a loop.")
    print("Runs named \"Code scanning AI findings\" are not PR checks and never block a merge.")
    if codeql_red:
        print("\nCodeQL alerts:")
        codeql_alerts(pr)
    for run_id, names in red_runs.items():
        if all(n.startswith("Analyze") for n in names):
            continue
        print(f"\nRun {run_id} ({', '.join(names)}):")
        triage_log(gh("run", "view", run_id, "--log-failed"))
    if not blocking:
        print("\nNo required check is failing.")
    return 1 if blocking else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", nargs="?", help="pull request number or workflow run id")
    parser.add_argument("--log", help="read a saved --log-failed dump instead of calling gh")
    args = parser.parse_args()
    try:
        if args.log:
            with open(args.log, encoding="utf-8", errors="replace") as handle:
                return 1 if triage_log(handle.read()) else 0
        if not args.target or not args.target.isdigit():
            parser.error("give a pull request number, a run id, or --log FILE")
        # Pull request numbers are small; run ids are not.
        if len(args.target) < 7:
            return triage_pr(args.target)
        print(f"Run {args.target}:")
        return 1 if triage_log(gh("run", "view", args.target, "--log-failed")) else 0
    except RuntimeError as err:
        print(f"triage: {err}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
