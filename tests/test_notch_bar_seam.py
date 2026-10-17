"""The notch joins the bar without a hairline crossing the seam.

Two earlier PRs rounded the geometry, but the seam stayed because it is a
drawn stroke, not a gap: SignalSurface outlines all four edges, and the bar
styles passed no gap to their edge SignalLine, so a 1px line ran under the
notch. The fix is one rule for every style: the notch-facing edge is drawn
only by a SignalLine that breaks across the shared notch span, and no bar
surface draws its own border on that edge. When the notch is not joined the
span is 0 and the line stays continuous.

This test is static on purpose: it runs in CI, which has no `qs`. The live
probe that instantiates SignalLine with a gap and SignalSurface with the
edge border disabled is run by hand and recorded in the PR.
"""
import re
from pathlib import Path

QML = Path(__file__).resolve().parent.parent / "Configs" / "quickshell" / "aphotic"

STYLES = {
    "full": "modules/bar/BarWrapper.qml",
    "taskbar": "modules/bar/TaskbarBar.qml",
    "minimal": "modules/bar/MinimalBar.qml",
    "dock": "modules/bar/DockBar.qml",
    "capsule": "modules/bar/CapsuleBar.qml",
}

# SignalSurfaces in a style file that are not the bar's notch-facing surface,
# with the reason. The capsule's expanded media popout is a floating surface
# with no notch edge, so it keeps its full rounded border.
NOT_BAR_EDGE = {
    ("capsule", "popoutSurface"): "the expanded media popout, not the bar edge",
}

GAP = re.compile(r"gapLength:\s*root\.screenState\.notchSpan")
EDGE = re.compile(r"edge:\s*root\.notchEdge")


def _code(relative_path: str) -> str:
    """The file with // comments removed, so prose cannot satisfy a check."""
    text = (QML / relative_path).read_text(encoding="utf-8")
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def _blocks(text: str, kind: str):
    """Every `kind { ... }` block as (id, body), matched on real braces."""
    for m in re.finditer(rf"\b{kind}\s*\{{", text):
        depth, i = 1, m.end()
        while depth and i < len(text):
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        body = text[m.start():i]
        idm = re.search(r"^\s*id:\s*(\w+)", body, re.M)
        yield (idm.group(1) if idm else None), body


def _bar_edges(name: str, text: str):
    """The SignalSurfaces that draw an edge of the bar."""
    for sid, body in _blocks(text, "SignalSurface"):
        if (name, sid) in NOT_BAR_EDGE:
            continue
        yield sid, body


def test_every_style_ships_the_notch_edge_rule():
    for name, path in STYLES.items():
        text = _code(path)
        assert re.search(r"readonly property string notchEdge:", text), (
            f"{path} has no single notchEdge the surface and line share"
        )


def test_every_style_opens_the_gap_in_its_edge_line():
    for name, path in STYLES.items():
        text = _code(path)
        lines = [body for _, body in _blocks(text, "SignalLine")]
        matched = [b for b in lines if GAP.search(b) and EDGE.search(b)]
        assert matched, (
            f"{path} has no SignalLine on the notch edge that opens the shared "
            "notch span (gapLength: root.screenState.notchSpan)"
        )


def test_no_bar_edge_surface_draws_a_full_border_on_the_notch():
    for name, path in STYLES.items():
        text = _code(path)
        for sid, body in _bar_edges(name, text):
            bordered = not re.search(r"border\.width:\s*0\b", body)
            if not bordered:
                continue
            assert re.search(r"openEdge:\s*root\.notchEdge", body), (
                f"{path}:{sid or 'SignalSurface'} draws a full border but leaves "
                "no edge open; the notch edge must be the SignalLine's to draw"
            )
            assert re.search(r"horizontal:\s*(Settings|root)\.", body), (
                f"{path}:{sid or 'SignalSurface'} opens an edge but does not say "
                "which axis it runs on, so start/end cannot map to top/bottom"
            )


def test_the_notch_span_has_one_source():
    screen_state = _code("components/ScreenState.qml")
    assert re.search(r"property real notchSpan:\s*0", screen_state), (
        "ScreenState must own the shared notch span every bar reads"
    )
    notch = _code("modules/notch/Notch.qml")
    assert re.search(r'property:\s*"notchSpan"', notch), (
        "Notch must publish its span into ScreenState.notchSpan"
    )
    # The span math lives in Notch.qml alone; no style recomputes it.
    for name, path in STYLES.items():
        text = _code(path)
        assert GAP.search(text) or "border.width: 0" in text, (
            f"{path} does not read the shared notch span"
        )
        assert not re.search(r"\bwing\b", text), (
            f"{path} recomputes the notch span instead of reading ScreenState.notchSpan"
        )


def test_the_join_shares_one_tone():
    notch = _code("modules/notch/Notch.qml")
    assert re.search(r"root\.joined\s*\?\s*Colours\.signalStyle\.bar\b", notch), (
        "the joined notch fill must be Colours.signalStyle.bar"
    )
    for name, path in STYLES.items():
        text = _code(path)
        for sid, body in _bar_edges(name, text):
            tone = re.search(r"^\s*tone:\s*(.+?)\s*$", body, re.M)
            if tone:
                assert tone.group(1) == "Colours.signalStyle.bar", (
                    f"{path}:{sid or 'SignalSurface'} tints its fill, so it steps "
                    "in tone where the notch joins"
                )
