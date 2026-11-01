"""Settings decides which harnesses show and in what order.

Harnesses.ordered follows Settings.harnessEntries, then appends any
descriptor the entries don't name. Harnesses.visible drops the hidden ones,
and its first harness is the default. setOrder keeps entries for harnesses
that have no descriptor right now, so a plugin turned off and on again
comes back in its place.
"""
import shutil

import pytest
from test_harness_gate import _seed
from test_sonar_session import run_probe

PROBE = """import QtQuick
import Quickshell
import qs.services
import qs.services.ai
ShellRoot {
    id: root
    property var result: ({})
    property int ticks: 0
    property int phase: 0

    function ids(list) { return list.map(d => d.id); }

    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            root.ticks++;
            if (root.ticks > 40) {
                root.result.timeout = true;
                console.log("HARNESS_ORDER " + JSON.stringify(root.result));
                Qt.quit();
                return;
            }
            if (root.phase === 0) {
                if (Harnesses.harnesses.length !== 4)
                    return;
                root.result.defaultOrder = root.ids(Harnesses.visible);
                Settings.harnessEntries = [
                    { id: "amp", enabled: true },
                    { id: "gone", enabled: true },
                    { id: "pi", enabled: false }
                ];
                root.phase = 1;
                return;
            }
            root.result.ordered = Harnesses.ordered.map(o => [o.descriptor.id, o.enabled]);
            root.result.visible = root.ids(Harnesses.visible);
            Harnesses.setOrder([
                { id: "claude", enabled: true },
                { id: "amp", enabled: false },
                { id: "pi", enabled: false },
                { id: "omp", enabled: true }
            ]);
            root.result.entries = Settings.harnessEntries;
            root.result.visibleAfter = root.ids(Harnesses.visible);
            console.log("HARNESS_ORDER " + JSON.stringify(root.result));
            Qt.quit();
        }
    }
}
"""


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_settings_order_hides_and_keeps_undescribed_entries(tmp_path):
    _seed(tmp_path, plugin_names=("claude-hooks", "pi-hooks"), dropins=("amp.toml",))
    out = run_probe(tmp_path, PROBE, marker="HARNESS_ORDER", prefix="_harness_order_")

    assert "timeout" not in out, out
    assert out["defaultOrder"] == ["claude", "pi", "omp", "amp"], out
    assert out["ordered"] == [
        ["amp", True], ["pi", False], ["claude", True], ["omp", True],
    ], out
    assert out["visible"] == ["amp", "claude", "omp"], out
    assert out["entries"] == [
        {"id": "claude", "enabled": True},
        {"id": "amp", "enabled": False},
        {"id": "pi", "enabled": False},
        {"id": "omp", "enabled": True},
        {"id": "gone", "enabled": True},
    ], out
    assert out["visibleAfter"] == ["claude", "omp"], out
