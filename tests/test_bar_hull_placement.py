"""Hull has one placement: a horizontal bar on the top edge.

The ring and its corner zones are drawn around a top strip, so a side or
bottom dock would leave the frame wrapped around nothing. Settings holds
the placement for hull whichever control writes it, and leaves every
other layout free to move.
"""
import shutil

import pytest
from test_sonar_session import run_probe

PROBE = r"""import QtQuick
import Quickshell
import qs.services

ShellRoot {
    id: shell
    property var out: ({})
    property int step: 0
    readonly property var steps: [
        () => { Settings.barLayout = "capsule"; Settings.barHorizontal = false; },
        () => { Settings.barLayout = "hull"; },
        () => { shell.record("enterHull"); Settings.barHorizontal = false; },
        () => { shell.record("sideInHull"); Settings.barPositionBottom = true; },
        () => { shell.record("bottomInHull"); shell.out.fixed = Settings.barPlacementFixed; Settings.barLayout = "dock"; },
        () => { Settings.barPositionBottom = true; Settings.barHorizontal = false; },
        () => { shell.record("dockMoves"); shell.out.dockFixed = Settings.barPlacementFixed; }
    ]
    function record(key) {
        shell.out[key] = [Settings.barHorizontal, Settings.barPositionBottom];
    }
    Timer {
        interval: 1500; running: true
        onTriggered: tick.start()
    }
    Timer {
        id: tick
        interval: 50; repeat: true
        onTriggered: {
            if (shell.step >= shell.steps.length) {
                console.log("HULLPLACE " + JSON.stringify(shell.out));
                Qt.quit();
                return;
            }
            shell.steps[shell.step++]();
        }
    }
}
"""


@pytest.fixture(scope="module")
def placement(tmp_path_factory):
    if shutil.which("qs") is None:
        pytest.skip("Quickshell unavailable")
    return run_probe(tmp_path_factory.mktemp("hullplace"), PROBE, marker="HULLPLACE", prefix="_hullplace_")


def test_switching_to_hull_puts_the_bar_on_top(placement):
    assert placement["enterHull"] == [True, False]


def test_hull_refuses_a_side_or_bottom_dock(placement):
    assert placement["sideInHull"] == [True, False]
    assert placement["bottomInHull"] == [True, False]
    assert placement["fixed"] is True


def test_other_layouts_still_move(placement):
    assert placement["dockMoves"] == [False, True]
    assert placement["dockFixed"] is False
