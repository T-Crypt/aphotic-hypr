#!/usr/bin/env python3
from __future__ import annotations

import argparse
import math
import re
import sys
from collections import Counter

from _common import document_title, docs_path, flat_sections, markdown_files, read_lines


TOKEN_RE = re.compile(r"[\w-]+", re.UNICODE)
# Question words carry no topic; left in, they rank whichever section uses
# them most.
STOPWORDS = {"a", "an", "and", "are", "as", "at", "be", "by", "do", "does", "for", "from", "how",
             "i", "in", "is", "it", "of", "on", "or", "the", "this", "to", "was", "we", "what",
             "when", "where", "which", "who", "why", "with"}


def tokens(text: str) -> list[str]:
    return [token.casefold() for token in TOKEN_RE.findall(text)]


def main() -> int:
    parser = argparse.ArgumentParser(description="Search documentation sections with BM25")
    parser.add_argument("--docs")
    parser.add_argument("question")
    parser.add_argument("--budget", type=int, default=2000, metavar="TOKENS")
    args = parser.parse_args()
    if args.budget < 1:
        parser.error("--budget must be positive")
    docs = docs_path(args.docs)
    records = []
    for path in markdown_files(docs):
        lines = read_lines(path)
        relative = path.relative_to(docs).as_posix()
        for section in flat_sections(lines, document_title(lines, path)):
            terms = tokens(section.heading + "\n" + section.text)
            if terms:
                records.append((relative, section, terms, Counter(terms)))
    query = [t for t in tokens(args.question) if t not in STOPWORDS] or tokens(args.question)
    if not records or not query:
        return 0
    average = sum(len(item[2]) for item in records) / len(records)
    document_frequency = Counter()
    for term in set(query):
        document_frequency[term] = sum(term in item[3] for item in records)
    ranked = []
    for relative, section, terms, counts in records:
        score = 0.0
        for term in query:
            frequency = counts[term]
            if not frequency:
                continue
            frequency_docs = document_frequency[term]
            inverse = math.log(1 + (len(records) - frequency_docs + 0.5) / (frequency_docs + 0.5))
            denominator = frequency + 1.5 * (1 - 0.75 + 0.75 * len(terms) / average)
            score += inverse * frequency * 2.5 / denominator
        # A heading that names the topic outranks a passing mention in a
        # long body, which BM25's length penalty otherwise favours.
        for term in set(query) & set(tokens(section.heading)):
            frequency_docs = document_frequency[term]
            score += 2 * math.log(1 + (len(records) - frequency_docs + 0.5) / (frequency_docs + 0.5))
        if score:
            ranked.append((score, relative, section))
    ranked.sort(key=lambda item: (-item[0], item[1].casefold(), item[2].start))
    remaining = args.budget * 4
    pieces = []
    for _, relative, section in ranked:
        header = f"{relative}:{section.start}-{section.end}\n"
        block = header + section.text.rstrip() + "\n"
        if len(block) <= remaining:
            pieces.append(block)
            remaining -= len(block)
            continue
        if remaining > len(header):
            pieces.append((header + section.text)[:remaining])
            remaining = 0
        break
    output = "\n".join(piece.rstrip() for piece in pieces)
    if output:
        output += "\n"
    sys.stdout.write(output[: args.budget * 4])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
