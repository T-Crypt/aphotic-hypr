"""Every surface flag reports to Surfaces, and every surface that can take
the keyboard gives way to a blocking modal.

services/SurfacePolicy.js decides how surfaces coexist, but it only sees
the flags ScreenState forwards to it. A flag added to ScreenState without
its `Surfaces.track` line opens beside everything else again, silently;
a keyboard-taking window without `Surfaces.suppressed` in its `visible`
can steal Escape from the negotiation prompt. Both are one-line
omissions nothing else would catch.
"""
import re
from pathlib import Path

QML = Path(__file__).resolve().parent.parent / "Configs" / "quickshell" / "aphotic"
SCREEN_STATE = QML / "components" / "ScreenState.qml"
POLICY = QML / "services" / "SurfacePolicy.js"

# Flags on ScreenState that are not surfaces: the bar's own reveal and
# the OSD are ambient, never take the keyboard, never close anything.
NOT_SURFACES = {"bar", "osd"}

# Keyboard-taking windows that deliberately stay up under a blocking
# modal, with the reason.
NOT_SUPPRESSED = {
    "NegotiationWindow.qml": "is the blocking modal",
    "AreaPicker.qml": "a screenshot selection the user is mid-drag in; one-shot",
    "ColorPicker.qml": "a one-shot pick the user is mid-way through",
    "PluginFullscreenWindow.qml": "the idle surface; dismisses on any input",
}


def _flags() -> list[str]:
    text = SCREEN_STATE.read_text(encoding="utf-8")
    return [f for f in re.findall(r"^\s*property bool (\w+)", text, re.M) if f not in NOT_SURFACES]


def _policy_surfaces() -> set[str]:
    text = POLICY.read_text(encoding="utf-8")
    block = re.search(r"var SURFACES = \{(.*?)\n\};", text, re.S)
    assert block, "SURFACES table not found in SurfacePolicy.js"
    return set(re.findall(r"^\s*(\w+): \{role:", block.group(1), re.M))


def test_scan_finds_flags():
    assert len(_flags()) >= 10


def test_every_flag_is_tracked():
    text = SCREEN_STATE.read_text(encoding="utf-8")
    missing = []
    for flag in _flags():
        handler = f"on{flag[0].upper()}{flag[1:]}Changed: Surfaces.track(root, \"{flag}\", root.{flag})"
        if handler not in text:
            missing.append(flag)
    assert not missing, f"ScreenState flags not reported to Surfaces: {missing}"


def test_policy_and_flags_agree():
    flags = set(_flags())
    surfaces = _policy_surfaces()
    assert flags - surfaces == set(), f"flags with no role in SurfacePolicy.SURFACES: {sorted(flags - surfaces)}"
    assert surfaces - flags == set(), f"SurfacePolicy.SURFACES names no ScreenState flag: {sorted(surfaces - flags)}"


def test_keyboard_windows_yield_to_blocking_modal():
    offenders = []
    for path in sorted(QML.rglob("*.qml")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        if not re.search(r"WlrKeyboardFocus\.(OnDemand|Exclusive)", text):
            continue
        if path.name in NOT_SUPPRESSED:
            continue
        visible = re.search(r"^    visible:(.*)$", text, re.M)
        if not visible or "Surfaces.suppressed" not in visible.group(1):
            offenders.append(str(path.relative_to(QML)))
    assert not offenders, f"keyboard-taking windows that ignore Surfaces.suppressed: {offenders}"


def test_negotiation_holds_and_releases():
    text = (QML / "modules" / "negotiation" / "NegotiationWindow.qml").read_text(encoding="utf-8")
    assert 'Surfaces.hold("negotiation")' in text
    assert 'Surfaces.release("negotiation")' in text
