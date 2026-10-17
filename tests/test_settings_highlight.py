"""Settings search highlighting against the real Quickshell runtime, offscreen.

A search hit addresses a row by handing SettingsPanel a ``<category>//
<anchor>`` string, and the panel marks that row. Two hits that land in the
same category arrive as two string changes whose category part is equal, so
the panel must still clear the row the previous hit marked before it marks
the new one. This drives that path end to end over the Appearance pane's two
rows and asserts that only the second row carries the mark afterwards.

The probe runs under ``run_probe`` (tests/test_sonar_session.py), which sets
HOME to a throwaway directory and QT_QPA_PLATFORM to offscreen, so the live
settings.json and the desktop are untouched.
"""
import shutil
from pathlib import Path

import pytest
from test_sonar_session import run_probe


PROBE = """import QtQuick
import Quickshell
import qs.components
import qs.modules.settings

ShellRoot {
    id: root

    ScreenState { id: state; modelData: Quickshell.screens[0] }
    SettingsPanel { id: panel; screenState: state }

    property var result: ({})
    property bool done: false
    property int phase: 0
    property int waits: 0

    function collect(item, out): var {
        if (!item)
            return out;
        if (item.searchId !== undefined && String(item.searchId).length > 0)
            out.push(item);
        const kids = item.children ?? [];
        for (let i = 0; i < kids.length; i++)
            root.collect(kids[i], out);
        return out;
    }

    function row(id): var {
        const all = root.collect(panel, []);
        for (let i = 0; i < all.length; i++) {
            if (all[i].searchId === id)
                return all[i];
        }
        return null;
    }

    function finish(): void {
        if (root.done)
            return;
        root.done = true;
        console.log("SETTINGS_HIGHLIGHT " + JSON.stringify(root.result));
        Qt.quit();
    }

    Timer {
        interval: 50
        repeat: true
        running: !root.done
        onTriggered: {
            root.waits++;
            if (root.waits > 120) {
                root.result.timeout = true;
                root.finish();
                return;
            }
            if (root.phase === 0) {
                if (!root.row("communityThemes") || !root.row("browseWallpapers"))
                    return;
                root.phase = 1;
                panel.currentCategory = "appearance//communityThemes";
                return;
            }
            if (root.phase === 1) {
                const first = root.row("communityThemes");
                const second = root.row("browseWallpapers");
                if (!first || !second || !first.highlighted)
                    return;
                root.result.firstHighlighted = first.highlighted;
                root.result.secondBeforeSecond = second.highlighted;
                root.phase = 2;
                panel.currentCategory = "appearance//browseWallpapers";
                return;
            }
            if (root.phase === 2) {
                const first = root.row("communityThemes");
                const second = root.row("browseWallpapers");
                if (!second || !second.highlighted)
                    return;
                root.result.firstAfterSecond = first ? first.highlighted : null;
                root.result.secondAfterSecond = second.highlighted;
                root.finish();
            }
        }
    }
}
"""


def highlight(tmp_path: Path) -> dict:
    return run_probe(tmp_path, PROBE, marker="SETTINGS_HIGHLIGHT",
                     prefix="_settings_highlight_")


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_second_same_category_hit_clears_the_first(tmp_path):
    out = highlight(tmp_path)

    assert not out.get("timeout"), f"probe timed out: {out}"
    assert out["firstHighlighted"] is True, out
    assert out["secondBeforeSecond"] is False, (
        "a row that no search hit addressed carried the highlight")
    assert out["secondAfterSecond"] is True, out
    assert out["firstAfterSecond"] is False, (
        "the row from the previous same-category hit stayed highlighted")
