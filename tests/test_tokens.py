"""The numbered Aphotic scale, with the older scale names kept as aliases.

B67DB3Y adds the numbered steps to config/Tokens.qml and points the older
names at them. This test pins the numbers, the alias mapping and the corner
helpers so a sweep cannot silently change a value or drop an alias before
the call sites move.
"""

import re
from pathlib import Path

import pytest

TOKENS = (Path(__file__).resolve().parent.parent
          / "Configs" / "quickshell" / "aphotic" / "config" / "Tokens.qml")

SCALE = {"space1": 4, "space2": 8, "space3": 12, "space4": 16,
         "space5": 20, "space6": 28, "space7": 32, "space8": 48}

# The numbers the older names have always carried. Each aliases the step
# with the same value, so every existing call site keeps its number.
LEGACY = [("extraSmall", "space1"), ("small", "space2"), ("medium", "space3"),
          ("large", "space4"), ("largeIncreased", "space5"),
          ("extraLarge", "space6"), ("extraLargeIncreased", "space7"),
          ("extraExtraLarge", "space8")]

ALIAS_GROUPS = ("padding", "spacing", "rounding")


@pytest.fixture(scope="module")
def source():
    return TOKENS.read_text(encoding="utf-8")


def _block(source, name):
    """The body of ``readonly property QtObject <name>: QtObject { ... }``."""
    marker = f"readonly property QtObject {name}: QtObject {{"
    start = source.index(marker) + len(marker)
    depth = 1
    index = start
    while depth:
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        index += 1
    return source[start:index]


def test_scale_steps_hold_their_values(source):
    for name, value in SCALE.items():
        pattern = rf"readonly property int {name}: {value}\b"
        assert re.search(pattern, source), f"Tokens.{name} is missing or changed"


def test_legacy_names_alias_the_scale(source):
    for group in ALIAS_GROUPS:
        body = _block(source, group)
        for name, step in LEGACY:
            pattern = rf"readonly property int {name}: root\.{step}\b"
            assert re.search(pattern, body), (
                f"Tokens.{group}.{name} no longer aliases root.{step}"
            )


def test_rounding_full_is_unchanged(source):
    assert re.search(r"readonly property int full: 999999\b", _block(source, "rounding")), (
        "Tokens.rounding.full changed value"
    )


def test_corner_helpers_exist(source):
    assert re.search(r"function radiusFor\(corners, px\)", source), (
        "Tokens.radiusFor is missing"
    )
    assert re.search(r"function uiRadius\(px\)", source), (
        "Tokens.uiRadius is missing"
    )
