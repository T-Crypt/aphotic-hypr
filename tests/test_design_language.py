"""The shell is leaving Material behind, and the count may only fall.

A sweep this size regresses without anyone noticing: one new palette read, one
literal colour, one numeric radius, and the design language is less true than
it was the day before. This ratchet counts seven kinds of leftover, keeps the
counts in tests/design_language_baseline.json, and fails when a count rises. A
fall and a hold pass.

That is the trade-off the ticket asks for: a fall nobody re-baselines leaves
the baseline high, so the next change can add some back and still pass.
Re-baseline after a real fall with
`python3 tests/test_design_language.py --update`. The strict variant is one
line, comparing with `==` instead of `>`, which makes every PR carry its own
baseline diff and makes two open PRs conflict on the same file.

The file list comes from `git ls-files`, never from a walk of the repo root, so
a second checkout inside the tree is not counted twice. The walk is the
fallback for a machine without git.
"""

import argparse
import json
import re
import subprocess
import sys
from functools import lru_cache
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BASELINE = Path(__file__).resolve().parent / "design_language_baseline.json"
SCAN_ROOT = "Configs/quickshell"
SUFFIXES = (".qml", ".js")
SCHEMA = 1
SKIP_DIRS = (".git", "docs", ".claude", "node_modules")

HEX = re.compile(r"#[0-9a-fA-F]{3,8}\b")
RADIUS = re.compile(
    r"^(?:[^{}]*\{)?\s*(?:readonly\s+)?(?:property\s+(?:real|int)\s+)?"
    r"[A-Za-z_]*[Rr]adius\s*:\s*-?\d+(?:\.\d+)?\s*\}?\s*$"
)
M3 = re.compile(r"\bm3[A-Za-z0-9_]*\b")
STATE_LAYER = re.compile(r"\bStateLayer\b")
MATERIAL_ICON = re.compile(r"\bMaterialIcon\b")
# The Signal on/off flag PR #298 removed, in the six spellings it was read as.
# Zero today, so the first mention of it again fails.
SIGNAL_FLAG = re.compile(r"\b(?:barSignal|bar_signal|signalOn|signal_on|useSignal|use_signal)\b")
# Comments naming the design system this release removes. A deny list cannot
# name the other shells, so the row counts the word those comments use.
MATERIAL_WORD = re.compile(r"\bmaterial\b", re.I)


def split(text):
    """Comments blanked out of the code, and kept on their own.

    A string literal survives, so a URL in one does not look like a comment,
    and a colour inside a comment does not count as styling.
    """
    code = []
    comments = []
    i = 0
    end = len(text)

    while i < end:
        if text.startswith("//", i):
            stop = text.find("\n", i)
            stop = end if stop < 0 else stop
            code.append(" " * (stop - i))
            comments.append(text[i:stop])
            i = stop
        elif text.startswith("/*", i):
            stop = text.find("*/", i + 2)
            stop = end if stop < 0 else stop + 2
            chunk = text[i:stop]
            code.append(_blank(chunk))
            comments.append(chunk)
            i = stop
        elif text[i] in "\"'`":
            i = _copy_literal(text, i, code, comments)
        else:
            code.append(text[i])
            # A newline is kept, so a comment hit keeps its own line number and
            # its own text instead of collapsing into one line at the top.
            comments.append("\n" if text[i] == "\n" else " ")
            i += 1

    return "".join(code), "".join(comments)


def _blank(chunk):
    return "".join("\n" if char == "\n" else " " for char in chunk)


def _copy_literal(text, start, code, comments):
    quote = text[start]
    i = start + 1
    end = len(text)
    while i < end:
        if text[i] == "\\":
            i += 2
        elif text[i] == quote:
            i += 1
            break
        elif text[i] == "\n":
            break
        else:
            i += 1
    i = min(i, end)
    chunk = text[start:i]
    code.append(chunk)
    comments.append(_blank(chunk))
    return i


def statements(code):
    """(line number, statement) pairs, split on newlines and on `;`."""
    out = []
    for number, line in enumerate(code.splitlines(), start=1):
        for part in line.split(";"):
            if part.strip():
                out.append((number, part.strip()))
    return out


def _on_code(pattern, skip_names=()):
    def finder(rel, code, comments):
        if rel.rsplit("/", 1)[-1] in skip_names:
            return []
        return [(number, line.strip())
                for number, line in enumerate(code.splitlines(), start=1)
                for _ in pattern.finditer(line)]
    return finder


def _on_statements(pattern):
    def finder(rel, code, comments):
        return [(number, text) for number, text in statements(code) if pattern.match(text)]
    return finder


def _on_comments(pattern):
    def finder(rel, code, comments):
        return [(number, line.strip())
                for number, line in enumerate(comments.splitlines(), start=1)
                for _ in pattern.finditer(line)]
    return finder


CATEGORIES = {
    "hex_colours": _on_code(HEX),
    "numeric_radii": _on_statements(RADIUS),
    "m3_palette_reads": _on_code(M3, skip_names=("Colours.qml",)),
    "state_layer_uses": _on_code(STATE_LAYER, skip_names=("StateLayer.qml",)),
    "material_icon_uses": _on_code(MATERIAL_ICON, skip_names=("MaterialIcon.qml",)),
    "signal_flag_mentions": _on_code(SIGNAL_FLAG),
    "material_comments": _on_comments(MATERIAL_WORD),
}

# What to do about a hit, for the row whose name does not say it.
ADVICE = {
    "material_comments": (
        "reword the comment so it does not name the design system this release "
        "leaves behind"
    ),
}

# The ticket excludes the file that defines each thing from the count of its
# uses. A counter that stops skipping would count definitions as leftovers.
SKIPPED_BASENAMES = {
    "m3_palette_reads": "Colours.qml",
    "state_layer_uses": "StateLayer.qml",
    "material_icon_uses": "MaterialIcon.qml",
}

SAMPLES = {
    "hex_colours": ('color: "#ff0000"', ("// #ff0000",)),
    "numeric_radii": (
        "Rectangle { radius: 10 }",
        ("x: Config.vertical ? -radius : 0", "radius: Tokens.radius.md", "radius: 8 * 2"),
    ),
    "m3_palette_reads": ("color: Colours.palette.m3primary", ("color: Colours.palette.primary",)),
    "state_layer_uses": ("color: StateLayer.hover", ("color: Palette.StatesLayer",)),
    "material_icon_uses": ('MaterialIcon { name: "close" }', ("color: MaterialSymbols.dim",)),
    "signal_flag_mentions": ("visible: Settings.barSignal", ("visible: Settings.barSignals",)),
    "material_comments": ("// material", ("color: materialColour",)),
}


def _git_files():
    """Tracked files under the scan root, or None when git cannot answer."""
    try:
        done = subprocess.run(("git", "ls-files", "-z", "--", SCAN_ROOT),
                              cwd=ROOT, capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        return None
    rels = sorted(path for path in done.stdout.split("\0") if path.endswith(SUFFIXES))
    return tuple(rels) or None


def _walk_files():
    """The fallback for a machine without git."""
    found = []
    for path in (ROOT / SCAN_ROOT).rglob("*"):
        if not path.is_file() or path.suffix not in SUFFIXES:
            continue
        parts = path.relative_to(ROOT).parts
        if any(part in SKIP_DIRS for part in parts):
            continue
        # Every parent of the file, from the repo root down, with no segment
        # dropped: a nested checkout sits under `Configs/quickshell`, so probing
        # a path without `Configs` looks in the wrong place and counts it.
        if any((ROOT / Path(*parts[:i]) / ".git").exists() for i in range(1, len(parts))):
            continue
        found.append("/".join(parts))
    return tuple(sorted(found))


@lru_cache(maxsize=1)
def enumerate_files():
    rels = _git_files()
    return rels if rels is not None else _walk_files()


@lru_cache(maxsize=1)
def collect():
    """category -> file -> the hits in it, as (line number, text)."""
    files = enumerate_files()
    if not files:
        raise RuntimeError(
            f"no {SCAN_ROOT} sources to scan: git listed nothing and the walk found "
            "nothing. Run this from a checkout that has the shell in it."
        )
    hits = {name: {} for name in CATEGORIES}
    for rel in files:
        text = (ROOT / rel).read_text(encoding="utf-8", errors="ignore")
        code, comments = split(text)
        for name, finder in CATEGORIES.items():
            found = finder(rel, code, comments)
            if found:
                hits[name][rel] = found
    return hits


def scan():
    """category -> file -> number of hits."""
    return {name: {rel: len(found) for rel, found in files.items()}
            for name, files in collect().items()}


def clear_caches():
    enumerate_files.cache_clear()
    collect.cache_clear()


def totals(counts=None):
    counts = scan() if counts is None else counts
    return {name: sum(files.values()) for name, files in counts.items()}


def load_baseline():
    if not BASELINE.is_file():
        raise RuntimeError(
            f"no baseline at {BASELINE.relative_to(ROOT)}. Create it with "
            "`python3 tests/test_design_language.py --update`."
        )
    try:
        doc = json.loads(BASELINE.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise RuntimeError(
            f"{BASELINE.relative_to(ROOT)} cannot be read as JSON: {exc}. Rewrite it with "
            "`python3 tests/test_design_language.py --update`."
        ) from exc

    if doc.get("schema") != SCHEMA:
        raise RuntimeError(
            f"{BASELINE.relative_to(ROOT)} has schema {doc.get('schema')!r}, this test "
            f"writes {SCHEMA}. Rewrite it with "
            "`python3 tests/test_design_language.py --update`."
        )

    names = set(doc.get("categories", {}))
    missing = sorted(set(CATEGORIES) - names)
    unknown = sorted(names - set(CATEGORIES))
    if missing or unknown:
        raise RuntimeError(
            f"{BASELINE.relative_to(ROOT)} does not match the counters: missing {missing}, "
            f"unknown {unknown}. Rewrite it with "
            "`python3 tests/test_design_language.py --update`."
        )
    return doc


def baseline_totals():
    return {name: entry["total"] for name, entry in load_baseline()["categories"].items()}


def baseline_files():
    return {name: entry["files"] for name, entry in load_baseline()["categories"].items()}


def write_baseline(counts):
    doc = {
        "schema": SCHEMA,
        "note": (
            "Design language counts for the shell. Re-baseline with "
            "python3 tests/test_design_language.py --update."
        ),
        "categories": {
            name: {"total": sum(counts[name].values()),
                   "files": dict(sorted(counts[name].items()))}
            for name in CATEGORIES
        },
    }
    BASELINE.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")


def rises(baseline, current):
    """The categories whose total went up, each with the numbers behind it."""
    return [{"category": name, "baseline": baseline[name], "current": current[name],
             "delta": current[name] - baseline[name]}
            for name in CATEGORIES if current[name] > baseline[name]]


def render(baseline, counts):
    width = max(len(name) for name in CATEGORIES) + 2
    lines = [f"{'category':<{width}}{'files':>6}{'baseline':>10}{'current':>9}{'delta':>7}"]
    for name in CATEGORIES:
        total = sum(counts[name].values())
        delta = total - baseline[name]
        shown = f"{delta:+}" if delta else "0"
        lines.append(f"{name:<{width}}{len(counts[name]):>6}"
                     f"{baseline[name]:>10}{total:>9}{shown:>7}")
    return "\n".join(lines)


MAX_FILES = 10
MAX_LINES = 5


def rise_report(baseline, counts, old=None):
    """Why the ratchet failed: the table, the files that rose, and what to do."""
    rose = rises(baseline, totals(counts))
    count = len(rose)
    lines = [f"design language ratchet: {count} categor{'y' if count == 1 else 'ies'} rose",
             render(baseline, counts), ""]
    old = baseline_files() if old is None else old
    hits = collect()
    for row in rose[:MAX_FILES]:
        name = row["category"]
        lines.append(f"{name} rose in these files:")
        for rel, found in sorted(hits[name].items()):
            was = old.get(name, {}).get(rel, 0)
            if len(found) <= was:
                continue
            lines.append(f"  {rel}  was {was}, now {len(found)}")
            lines.extend(f"    {rel}:{number}: {text}" for number, text in found[:MAX_LINES])
            if len(found) > MAX_LINES:
                lines.append(f"    ... {len(found) - MAX_LINES} more hits in this file, see "
                             f"python3 tests/test_design_language.py --list {name}")
        if name in ADVICE:
            lines.append(f"  {ADVICE[name]}")
        lines.append("")
    lines.append("re-baseline only if the rise is deliberate: "
                 "python3 tests/test_design_language.py --update --allow-rise")
    return "\n".join(lines)


def _count(name, text, rel="tests/sample.qml"):
    code, comments = split(text)
    return len(CATEGORIES[name](rel, code, comments))


@pytest.fixture(scope="session", autouse=True)
def delta_table():
    """Every run prints the counts, so a PR author can paste the table."""
    print(render(baseline_totals(), scan()))


def test_scan_covers_the_shell_tree():
    files = enumerate_files()
    assert len(files) >= 300, (
        f"only {len(files)} files under {SCAN_ROOT}: the file list is broken, and "
        "every count below would pass by being empty"
    )
    assert f"{SCAN_ROOT}/aphotic/services/Colours.qml" in files, (
        "the shell's palette is missing from the file list"
    )


def test_every_counter_reads_its_samples():
    for name, (positive, negatives) in SAMPLES.items():
        assert _count(name, positive) == 1, f"{name} no longer matches {positive!r}"
        for negative in negatives:
            assert _count(name, negative) == 0, f"{name} matches {negative!r}, which is not one"
    for name, basename in SKIPPED_BASENAMES.items():
        assert _count(name, SAMPLES[name][0], rel=f"tests/{basename}") == 0, (
            f"{name} counts the file that defines it"
        )


def test_comment_split_keeps_string_literals():
    text = ('source: "https://example/x" // gone\n'
            'color: 1 /* #ff0000 */\n'
            '// material\n')
    code, comments = split(text)
    assert "https://example/x" in code
    assert "gone" not in code
    assert "#ff0000" not in code
    assert "gone" in comments
    assert "#ff0000" in comments
    lines = comments.splitlines()
    assert len(lines) == len(text.splitlines()), (
        "the comments stream lost its line structure, so every hit reports line 1 and the "
        "whole file's comments as its text"
    )
    assert lines[0].strip() == "// gone", "the // inside the string literal became a comment"
    assert lines[2].strip() == "// material"


def test_comment_hits_report_their_own_line():
    text = "color: 1\n// nothing to see\n// material leftover\n"
    code, comments = split(text)
    found = CATEGORIES["material_comments"]("tests/sample.qml", code, comments)
    assert found == [(3, "// material leftover")]


def test_baseline_matches_the_counters():
    doc = load_baseline()
    assert doc["schema"] == SCHEMA
    assert sorted(doc["categories"]) == sorted(CATEGORIES)
    for name, entry in doc["categories"].items():
        assert entry["total"] >= 0, f"{name} has a negative total"
        counted = sum(entry["files"].values())
        assert counted == entry["total"], (
            f"{name} says total {entry['total']}, its per-file counts add up to {counted}. "
            "The total decides pass or fail, so it cannot be raised by hand: rewrite the "
            "baseline with `python3 tests/test_design_language.py --update`."
        )


@pytest.mark.parametrize("category", list(CATEGORIES))
def test_no_category_rises_above_the_baseline(category):
    baseline = baseline_totals()
    assert category not in [row["category"] for row in rises(baseline, totals())], (
        rise_report(baseline, scan())
    )


@pytest.mark.parametrize("move,before,after", [("hold", 10, 10), ("fall", 10, 7), ("rise", 10, 13)])
def test_no_category_rises_on_synthetic_counts(move, before, after):
    """The comparison both ways, so a fall and a hold are covered without QML."""
    baseline = {name: before for name in CATEGORIES}
    current = {name: after for name in CATEGORIES}
    rose = rises(baseline, current)
    if move == "rise":
        assert len(rose) == len(CATEGORIES)
    else:
        assert not rose


def test_walk_fallback_skips_a_nested_checkout(tmp_path, monkeypatch):
    kept = tmp_path / "Configs/quickshell/aphotic/Kept.qml"
    kept.parent.mkdir(parents=True)
    kept.write_text("Item {}\n", encoding="utf-8")
    nested = tmp_path / "Configs/quickshell/aphotic/modules/nested"
    nested.mkdir(parents=True)
    (nested / "Copy.qml").write_text('color: "#ff0000"\n', encoding="utf-8")
    (nested / ".git").write_text("gitdir: elsewhere\n", encoding="utf-8")
    monkeypatch.setattr(sys.modules[__name__], "ROOT", tmp_path)
    monkeypatch.setattr(sys.modules[__name__], "SCAN_ROOT", "Configs/quickshell")
    assert _walk_files() == ("Configs/quickshell/aphotic/Kept.qml",), (
        "the walk counted a second checkout inside the scan root"
    )


def test_walk_fallback_agrees_with_git():
    tracked = _git_files()
    if tracked is None:
        pytest.skip("git is not available")
    assert set(_walk_files()) == set(tracked), (
        "the walk and git ls-files disagree, so the fallback counts different files"
    )


def test_an_empty_tree_fails_loudly(monkeypatch):
    clear_caches()
    monkeypatch.setattr(sys.modules[__name__], "enumerate_files", lambda: ())
    try:
        with pytest.raises(RuntimeError, match="sources to scan"):
            collect()
    finally:
        monkeypatch.undo()
        clear_caches()


def update(allow_rise):
    doc = None
    if not BASELINE.is_file():
        print("no baseline yet, writing the first one", file=sys.stderr)
    else:
        try:
            doc = load_baseline()
        except RuntimeError as exc:
            print(exc, file=sys.stderr)
            print("counting against an empty baseline, so every category rose", file=sys.stderr)

    old = {} if doc is None else {name: entry["files"]
                                  for name, entry in doc["categories"].items()}
    baseline = {name: sum(old.get(name, {}).values()) for name in CATEGORIES}

    current = scan()
    now = totals(current)
    if doc is not None and not allow_rise and rises(baseline, now):
        print(rise_report(baseline, current, old), file=sys.stderr)
        print("refusing to raise a count without --allow-rise", file=sys.stderr)
        return 1

    for name in CATEGORIES:
        print(f"{name} {baseline[name]} -> {now[name]} ({now[name] - baseline[name]:+})")
    if doc is not None:
        for name in CATEGORIES:
            for rel, count in sorted(current[name].items()):
                was = old.get(name, {}).get(rel)
                if was != count:
                    print(f"  {name}: {rel} {was or 0} -> {count}")
    write_baseline(current)
    print(f"wrote {BASELINE.relative_to(ROOT)}")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Count the shell's Material leftovers and compare with the baseline."
    )
    parser.add_argument("--print", dest="print_only", action="store_true",
                        help="print the counts and stop")
    parser.add_argument("--list", metavar="CATEGORY", help="print every hit in one category")
    parser.add_argument("--update", action="store_true",
                        help="write the baseline from the counts on disk now")
    parser.add_argument("--allow-rise", action="store_true",
                        help="let --update take a total that went up")
    args = parser.parse_args(argv)

    if args.list:
        if args.list not in CATEGORIES:
            print(f"unknown category {args.list}; try {', '.join(CATEGORIES)}", file=sys.stderr)
            return 2
        for rel, found in sorted(collect()[args.list].items()):
            for number, text in found:
                print(f"{rel}:{number}: {text}")
        return 0

    if args.update:
        return update(args.allow_rise)

    current = scan()
    if args.print_only:
        try:
            baseline = baseline_totals()
        except RuntimeError:
            print("no baseline yet, so every delta below is against zero", file=sys.stderr)
            baseline = {name: 0 for name in CATEGORIES}
        print(render(baseline, current))
        return 0

    baseline = baseline_totals()
    if rises(baseline, totals(current)):
        print(rise_report(baseline, current))
        return 1

    print(render(baseline, current))
    print("every count is at or below the baseline. After a fall, re-baseline with "
          "`python3 tests/test_design_language.py --update` so the next change has to "
          "hold the new floor.")
    return 0


def entry():
    try:
        return main()
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(entry())
