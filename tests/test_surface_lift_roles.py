"""surfaceLift is the lifted surface role, and tPalette stays internal.

Colours.surface is the flat base container. Colours.surfaceLift is the same
container with one layer of primary tint, which is what every former
tPalette.m3surfaceContainer read showed before the role split. Two things hold
from here on: components that want the lifted value read surfaceLift, and no
QML outside services/Colours.qml reaches into the palette objects at all.

The first check fails if the role loses every caller and dies. The second
fails on any new m3 palette read through tPalette, so the next sweep cannot
reintroduce the pattern the colour roles exist to replace.
"""

import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SCAN_ROOT = "Configs/quickshell"
COLOURS = "Configs/quickshell/aphotic/services/Colours.qml"
LIFT = re.compile(r"\bColours\.surfaceLift\b")
TPALETTE = re.compile(r"\btPalette\s*\.")


def qml_files():
    out = subprocess.run(
        ["git", "ls-files", "Configs/quickshell/aphotic/*.qml"], cwd=ROOT,
        capture_output=True, text=True,
    )
    if out.returncode == 0 and out.stdout.strip():
        return [line for line in out.stdout.splitlines() if line.endswith(".qml")]
    return [str(p.relative_to(ROOT)) for p in (ROOT / SCAN_ROOT).rglob("*.qml")]


def code_lines(text):
    """Lines with // comments removed, so a mention in prose does not count."""
    for line in text.splitlines():
        yield line.split("//", 1)[0]


@pytest.fixture(scope="module")
def sources():
    return {path: (ROOT / path).read_text() for path in qml_files()}


def test_surface_lift_has_call_sites(sources):
    sites = [(path, line)
             for path, text in sources.items() if path != COLOURS
             for line in code_lines(text) if LIFT.search(line)]
    assert sites, "no component reads Colours.surfaceLift"


def test_no_tpalette_reads_outside_colours(sources):
    reads = [(path, number, line.strip())
             for path, text in sources.items() if path != COLOURS
             for number, line in enumerate(code_lines(text), start=1)
             if TPALETTE.search(line)]
    assert not reads, "tPalette reads outside services/Colours.qml:\n" + "\n".join(
        f"  {path}:{number}: {line}" for path, number, line in reads)
