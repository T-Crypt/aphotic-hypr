#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


HEADING_RE = re.compile(r"^(#{1,3})\s+(.+?)\s*$")
ACTIVE_DOC_DIRS = {"playbooks", "reference"}


@dataclass(frozen=True)
class Heading:
    level: int
    title: str
    start: int
    end: int


@dataclass(frozen=True)
class Section:
    heading: str
    start: int
    end: int
    text: str


def run_git(args: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def repository_root() -> Path:
    top = run_git(["rev-parse", "--show-toplevel"])
    if top.returncode:
        raise RuntimeError("not inside a git checkout")
    return Path(top.stdout.strip()).resolve()


def main_checkout_root() -> Path:
    top = repository_root()
    common = run_git(["rev-parse", "--git-common-dir"], cwd=top)
    if common.returncode:
        return top
    common_path = Path(common.stdout.strip())
    if not common_path.is_absolute():
        common_path = top / common_path
    common_path = common_path.resolve()
    return common_path.parent if common_path.name == ".git" else top


def docs_path(value: str | None) -> Path:
    selected = value or os.environ.get("APHOTIC_DOCS")
    path = Path(selected).expanduser() if selected else main_checkout_root() / "docs"
    return path.resolve()


def markdown_files(docs: Path) -> list[Path]:
    files = []
    for path in docs.rglob("*.md"):
        relative = path.relative_to(docs)
        if path.name == "INDEX.md" or ".git" in relative.parts:
            continue
        if len(relative.parts) > 1 and relative.parts[0] not in ACTIVE_DOC_DIRS:
            continue
        if path.is_file():
            files.append(path)
    return sorted(files, key=lambda item: item.relative_to(docs).as_posix().casefold())


def read_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)


def line_text(lines: list[str]) -> list[str]:
    return [line.rstrip("\r\n") for line in lines]


def document_title(lines: list[str], path: Path) -> str:
    for line in line_text(lines):
        match = re.match(r"^#\s+(.+?)\s*$", line)
        if match:
            return match.group(1)
    return path.stem.replace("_", " ").replace("-", " ").strip().title()


def _plain_markdown(text: str) -> str:
    text = re.sub(r"!\[([^]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"\[([^]]+)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"[*_`]+", "", text)
    return re.sub(r"\s+", " ", text).strip()


def document_purpose(lines: list[str], limit: int = 120) -> str:
    plain = line_text(lines)
    paragraph: list[str] = []
    in_fence = False
    for raw in plain:
        stripped = raw.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence or not stripped:
            if paragraph:
                break
            continue
        if stripped.startswith("#") or stripped in {"---", "***", "___"}:
            if paragraph:
                break
            continue
        if stripped.startswith(("<!--", "|", "- ", "* ", "+ ")) or re.match(r"^\d+[.)]\s", stripped):
            if paragraph:
                break
            continue
        paragraph.append(stripped.lstrip("> "))
    purpose = _plain_markdown(" ".join(paragraph)) or "No purpose stated."
    sentence = re.split(r"(?<=[.!?])\s+", purpose, maxsplit=1)[0]
    if len(sentence) <= limit:
        return sentence
    return sentence[: limit - 3].rstrip() + "..."


def headings(lines: list[str]) -> list[Heading]:
    plain = line_text(lines)
    found: list[tuple[int, str, int]] = []
    in_fence = False
    for number, raw in enumerate(plain, 1):
        if raw.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        match = HEADING_RE.match(raw)
        if match and len(match.group(1)) in (2, 3):
            found.append((len(match.group(1)), match.group(2).strip().rstrip("#").strip(), number))
    result: list[Heading] = []
    for index, (level, title, start) in enumerate(found):
        end = len(plain)
        for next_level, _, next_start in found[index + 1 :]:
            if next_level <= level:
                end = next_start - 1
                break
        result.append(Heading(level, title, start, end))
    return result


def flat_sections(lines: list[str], fallback: str) -> list[Section]:
    plain = line_text(lines)
    starts: list[tuple[int, str]] = []
    in_fence = False
    for number, raw in enumerate(plain, 1):
        if raw.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        match = HEADING_RE.match(raw)
        if match and len(match.group(1)) in (2, 3):
            starts.append((number, match.group(2).strip().rstrip("#").strip()))
    sections: list[Section] = []
    first = starts[0][0] if starts else len(plain) + 1
    if first > 1:
        text = "\n".join(plain[: first - 1]).strip()
        if text:
            sections.append(Section(fallback, 1, first - 1, text))
    for index, (start, title) in enumerate(starts):
        end = starts[index + 1][0] - 1 if index + 1 < len(starts) else len(plain)
        sections.append(Section(title, start, end, "\n".join(plain[start - 1 : end]).rstrip()))
    return sections


def resolve_document(docs: Path, value: str) -> Path:
    candidate = Path(value).expanduser()
    path = candidate.resolve() if candidate.is_absolute() else (docs / candidate).resolve()
    try:
        path.relative_to(docs)
    except ValueError as error:
        raise ValueError(f"file is outside docs: {value}") from error
    if not path.is_file():
        raise FileNotFoundError(value)
    return path


def mtime_date(path: Path) -> str:
    return datetime.fromtimestamp(path.stat().st_mtime).date().isoformat()
