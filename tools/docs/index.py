#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from _common import document_purpose, document_title, docs_path, headings, markdown_files, mtime_date, read_lines


MAX_INDEX_BYTES = 24 * 1024
MIN_HEADING = 36


def shortened(value: str, limit: int) -> str:
    if len(value) <= limit:
        return value
    if limit < 2:
        return value[:limit]
    return value[: limit - 1].rstrip() + "…"


def render(entries: list[dict[str, object]], limits: dict[str, int], shown: dict[str, list]) -> str:
    output = [
        "# Documentation index",
        "",
        "Live scope: root files, `playbooks/`, and `reference/`; retired and imported trees stay out of search.",
        "Read a section with `tools/docs/section.py`; search with `tools/docs/ask.py`.",
        "",
    ]
    for entry in entries:
        path = str(entry["path"])
        output.append(
            f"- `{path}` | {shortened(str(entry['title']), 72)} | "
            f"{shortened(str(entry['purpose']), 56)} | {entry['mtime']} | {entry['lines']} lines"
        )
        sections = shown[path]
        hidden = len(entry["sections"]) - len(sections)
        if sections:
            cap = limits[path]
            compact = "; ".join(
                f"{item['start']}-{item['end']}:{shortened(str(item['heading']), cap)}" for item in sections
            )
            output.append(f"  {compact}" + (f" (+{hidden} subsections)" if hidden else ""))
    return "\n".join(output).rstrip() + "\n"


def build_index(docs: Path) -> tuple[str, dict[str, object]]:
    entries = []
    for path in markdown_files(docs):
        lines = read_lines(path)
        relative = path.relative_to(docs).as_posix()
        title = document_title(lines, path)
        purpose = document_purpose(lines)
        found = headings(lines)
        date = mtime_date(path)
        count = len(lines)
        entries.append(
            {
                "path": relative,
                "title": title,
                "purpose": purpose,
                "mtime": date,
                "lines": count,
                "sections": [
                    {"level": item.level, "heading": item.title, "start": item.start, "end": item.end}
                    for item in found
                ],
            }
        )
    limits = {str(entry["path"]): 80 for entry in entries}
    shown = {str(entry["path"]): entry["sections"] for entry in entries}
    markdown = render(entries, limits, shown)
    # A heading cut to a few characters tells a reader nothing, so a large
    # file first loses its subsections (counted, not listed), and only then
    # do headings shorten, never below MIN_HEADING.
    while len(markdown.encode("utf-8")) > MAX_INDEX_BYTES:
        deep = [e for e in entries if any(s["level"] > 2 for s in shown[str(e["path"])])]
        if deep:
            largest = max(deep, key=lambda e: len(shown[str(e["path"])]))
            key = str(largest["path"])
            shown[key] = [s for s in shown[key] if s["level"] <= 2]
        else:
            candidates = [e for e in entries if shown[str(e["path"])] and limits[str(e["path"])] > MIN_HEADING]
            if not candidates:
                raise RuntimeError("documentation index cannot fit within 24 KiB")
            largest = max(candidates, key=lambda e: len(shown[str(e["path"])]) * limits[str(e["path"])])
            key = str(largest["path"])
            limits[key] = max(MIN_HEADING, limits[key] - 4)
        markdown = render(entries, limits, shown)
    return markdown, {"files": entries}


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the local documentation index")
    parser.add_argument("--docs")
    args = parser.parse_args()
    docs = docs_path(args.docs)
    docs.mkdir(parents=True, exist_ok=True)
    markdown, data = build_index(docs)
    (docs / "INDEX.md").write_text(markdown, encoding="utf-8")
    (docs / ".index.json").write_text(
        json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
