"""A read of plugins.json that fails must not empty the shell's plugin registry.

The CLI rewrites ~/.local/state/aphotic/plugins.json from another process and
PluginRegistry.qml watches it with a FileView. Until 2026-10-13 a parse failure
or a failed load reset the registry to {}, which reads as "nothing is
installed" across the whole shell at once: every dashboard tab, notch tile and
workspace surface gone until the next successful read.

The probe loads a two-plugin registry, has a separate process overwrite the
file with garbage, and records what the shell still reports. It then writes a
valid registry back through the same path, so a fix that wedges the watch
instead of keeping the last good data fails the last assertion too.
"""
import json
import shutil
from pathlib import Path

import pytest

from test_sonar_session import run_probe

ROOT = Path(__file__).resolve().parents[1]

GOOD = {"disabled": ["beta"], "installed": {"alpha": {"version": "1.0.0"},
                                            "beta": {"version": "1.0.0"}}}
LATER = {"disabled": [], "installed": {"alpha": {}, "beta": {}, "gamma": {}}}

PROBE = '''import QtQuick
import Quickshell
import qs.components
import qs.services
ShellRoot {
    id: root
    property int phase: 0
    property int waited: 0
    property var result: ({})
    readonly property string registryPath: Quickshell.env("HOME") + "/.local/state/aphotic/plugins.json"
    readonly property var write: (text) => ["sh", "-c", "printf '%s' '" + text + "' > '" + root.registryPath + ".new' && mv '" + root.registryPath + ".new' '" + root.registryPath + "'"]
    function snapshot() {
        return {
            installed: Object.keys(PluginRegistry._installed).length,
            disabled: PluginRegistry._disabled.length
        };
    }
    Timer {
        interval: 250; repeat: true; running: true
        onTriggered: {
            if (root.phase === 0) {
                if (Object.keys(PluginRegistry._installed).length === 0) return;
                root.result.loaded = root.snapshot();
                Quickshell.execDetached(root.write("not json at all"));
                root.phase = 1;
                return;
            }
            if (++root.waited < 8) return;
            root.waited = 0;
            if (root.phase === 1) {
                root.result.afterBadRead = root.snapshot();
                Quickshell.execDetached(root.write('{\"disabled\":[],\"installed\":{\"alpha\":{},\"beta\":{},\"gamma\":{}}}'));
                root.phase = 2;
                return;
            }
            root.result.afterGoodRead = root.snapshot();
            console.log("PLUGIN_REGISTRY " + JSON.stringify(root.result));
            Qt.quit();
        }
    }
    Timer {
        interval: 10000; running: true
        onTriggered: { console.log("PLUGIN_REGISTRY " + JSON.stringify({timeout: true})); Qt.quit(); }
    }
}'''


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_bad_registry_read_keeps_last_good_data(tmp_path):
    state = tmp_path / "home/.local/state/aphotic"
    state.mkdir(parents=True)
    (state / "plugins.json").write_text(json.dumps(GOOD))

    out = run_probe(tmp_path, probe_text=PROBE, marker="PLUGIN_REGISTRY",
                    prefix="_plugin_registry_")

    assert not out.get("timeout"), f"probe timed out: {out}"
    loaded = {"installed": len(GOOD["installed"]), "disabled": len(GOOD["disabled"])}
    assert out.get("loaded") == loaded, f"the probe never saw the registry: {out}"
    assert out.get("afterBadRead") == loaded, (
        "a half-written or unparsable plugins.json blanked the registry instead "
        f"of keeping the last good read: {out}")
    later = {"installed": len(LATER["installed"]), "disabled": len(LATER["disabled"])}
    assert out.get("afterGoodRead") == later, (
        f"the watch stopped picking the registry up after a bad read: {out}")
