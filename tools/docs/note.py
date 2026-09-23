#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import textwrap
from datetime import date

from _common import docs_path


FILES = {
    "ledger": "LEDGER.md",
    "knowledge": "KNOWLEDGE_BASE.md",
    "decision": "DECISIONS.md",
    "issue": "ISSUES.md",
    "status": "STATUS.md",
}


def entry(kind: str, text: str, current: str) -> str:
    today = date.today().isoformat()
    if kind == "decision":
        numbers = [int(value) for value in re.findall(r"\bD-(\d+)\b", current)]
        # The first sentence is the heading; the rest is the body, so a long
        # decision does not become one unreadable heading line.
        title, _, body = text.partition(". ")
        heading = f"### D-{max(numbers, default=0) + 1:02d} · {today} · {title.rstrip('.')}\n"
        return heading + (f"\n{textwrap.fill(body, 78)}\n" if body else "")
    if kind == "status":
        return f"### Session note · {today}\n{text}\n"
    return f"### {today} · {text}\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Append a dated documentation note")
    parser.add_argument("--docs")
    parser.add_argument("--kind", choices=sorted(FILES), required=True)
    parser.add_argument("text")
    args = parser.parse_args()
    target = docs_path(args.docs) / FILES[args.kind]
    current = target.read_text(encoding="utf-8") if target.exists() else ""
    separator = "" if not current or current.endswith("\n\n") else "\n" if current.endswith("\n") else "\n\n"
    with target.open("a", encoding="utf-8") as handle:
        handle.write(separator + entry(args.kind, args.text, current))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

