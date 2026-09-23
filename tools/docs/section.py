#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys

from _common import docs_path, headings, read_lines, resolve_document


def main() -> int:
    parser = argparse.ArgumentParser(description="Print one documentation section")
    parser.add_argument("--docs")
    parser.add_argument("file")
    parser.add_argument("selector")
    args = parser.parse_args()
    docs = docs_path(args.docs)
    path = resolve_document(docs, args.file)
    lines = read_lines(path)
    range_match = re.fullmatch(r"(\d+)-(\d+)", args.selector)
    if range_match:
        start, end = map(int, range_match.groups())
        if start < 1 or end < start or end > len(lines):
            parser.error(f"line range must be within 1-{len(lines)}")
    else:
        wanted = args.selector.casefold().strip()
        match = next((item for item in headings(lines) if item.title.casefold() == wanted), None)
        if match is None:
            print(f"heading not found: {args.selector}", file=sys.stderr)
            return 1
        start, end = match.start, match.end
    sys.stdout.write("".join(lines[start - 1 : end]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

