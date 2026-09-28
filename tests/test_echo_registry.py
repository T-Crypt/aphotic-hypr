"""EchoRegistry's register/update/unregister and revocation, against the
real Quickshell runtime.

The node policy tests prove the pure rules; this one proves the QML
singleton actually wires them: PluginRegistry's state file feeds
eligibility, a target's action must be a surface its plugin declared,
and a grant dropped from the state file while the plugin stays enabled
revokes its live records.
"""
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
QML_ROOT = ROOT / "Configs/quickshell/aphotic"
STATE_DIR = ".local/state/aphotic"
SAMPLE_API_V2 = {"version": 2, "uses": ["surface.declare", "sonar.register"]}

PROBE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
    id: root

    property var results: ({})
    property bool done: false
    property int ticks: 0
    // Phase 1 runs the CRUD checks as soon as the registry sees the
    // plugin; phase 2 rewrites the state file and waits for revocation.
    property int phase: 0
    property bool ready: EchoRegistry.eligiblePlugins.includes("sample")

    function descriptor(action) {
        return {label: "Panel", output: "DP-2",
            rect: {x: 0, y: 0, width: 100, height: 40}, action: action};
    }

    function finish(extra) {
        if (root.done)
            return;
        root.done = true;
        console.log("SONAR_PROBE " + JSON.stringify(Object.assign({}, root.results, extra)));
        Qt.quit();
    }

    onReadyChanged: () => {
        if (!root.ready || root.phase !== 0)
            return;
        root.phase = 1;
        const api = PluginApi.handle("sample");
        const results = {
            declare: api.surfaces.declare("panel", "transient"),
            register: EchoRegistry.register("sample", "panel", root.descriptor("plugin:sample/panel")),
            registerForeignAction: EchoRegistry.register("sample", "ghost",
                root.descriptor("plugin:sample/nowhere")),
            updateUnknown: EchoRegistry.update("sample", "ghost", root.descriptor("plugin:sample/panel")),
            update: EchoRegistry.update("sample", "panel",
                Object.assign(root.descriptor("plugin:sample/panel"), {label: "Panel 2"})),
            label: EchoRegistry.records["plugin:sample/panel"]?.label ?? "",
            snapshotLabels: EchoRegistry.snapshot().map(t => t.label),
            afterUnregister: (EchoRegistry.unregister("sample", "panel"),
                Object.keys(EchoRegistry.records).length),
            // Leave one live record for phase 2 to revoke.
            reRegister: EchoRegistry.register("sample", "panel", root.descriptor("plugin:sample/panel")),
        };
        root.results = results;
        root.phase = 2;
    }

    Timer {
        interval: 100
        running: root.phase === 2 && !root.done
        repeat: true
        onTriggered: {
            root.ticks += 1;
            if (root.ticks === 1) {
                // The grant is dropped while the plugin stays installed
                // and enabled -- the state file is what the CLI's resync
                // and update rewrite.
                Qt.callLater(() => rewrite.running = true);
            }
            const count = Object.keys(EchoRegistry.records).length;
            if (count === 0) {
                root.finish({
                    revoked: true,
                    reRegisterWithoutGrant: EchoRegistry.register("sample", "panel",
                        root.descriptor("plugin:sample/panel")),
                });
            } else if (root.ticks > 40) {
                root.finish({revoked: false, recordCount: count});
            }
        }
    }

    Timer {
        interval: 8000
        running: !root.done
        onTriggered: root.finish({timeout: true})
    }

    Process {
        id: rewrite
        command: ["cp",
            Quickshell.env("HOME") + "/$STATE_DIR/revoked.json",
            Quickshell.env("HOME") + "/$STATE_DIR/plugins.json"]
    }

    Component.onCompleted: () => { if (root.ready) root.onReadyChanged() }
}
"""


def write_state(home: Path, name: str, installed: dict) -> Path:
    state = home / STATE_DIR
    state.mkdir(parents=True, exist_ok=True)
    path = state / name
    path.write_text(json.dumps({"installed": installed}))
    return path


def run_probe(home: Path) -> dict:
    probe = tempfile.NamedTemporaryFile(
        mode="w", suffix=".qml", prefix="_echo_registry_",
        dir=QML_ROOT, delete=False,
    )
    try:
        probe.write(PROBE.replace("$STATE_DIR", STATE_DIR))
        probe.close()
        env = os.environ.copy()
        env["HOME"] = str(home)
        env["XDG_CACHE_HOME"] = str(home / ".cache")
        env["XDG_DATA_HOME"] = str(home / ".local/share")
        env["XDG_RUNTIME_DIR"] = str(home / "runtime")
        env["QT_QPA_PLATFORM"] = "offscreen"
        result = subprocess.run(
            ["timeout", "20", "qs", "-p", Path(probe.name).name],
            cwd=QML_ROOT, env=env, capture_output=True, text=True, check=False,
        )
    finally:
        Path(probe.name).unlink(missing_ok=True)

    raw = result.stdout + "\n" + result.stderr
    lines = [l.split("SONAR_PROBE ", 1)[1]
             for l in raw.splitlines() if "SONAR_PROBE " in l]
    assert lines, (
        "probe never reported\n"
        f"qs exited {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return json.loads(lines[-1].removeprefix("SONAR_PROBE "))


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_echo_registry_crud_and_revocation(tmp_path):
    home = tmp_path / "home"
    (home / "runtime").mkdir(mode=0o700, parents=True)
    write_state(home, "plugins.json", {
        "sample": {"display_name": "Sample", "api": SAMPLE_API_V2},
    })
    write_state(home, "revoked.json", {
        "sample": {"display_name": "Sample",
                   "api": {"version": 1, "uses": ["surface.declare", "sonar.register"]}},
    })

    out = run_probe(home)

    assert not out.get("timeout"), f"probe timed out: {out}"
    assert out["declare"] is True
    assert out["register"] is True
    # An action the plugin never declared is refused at registration.
    assert out["registerForeignAction"] is False
    assert out["updateUnknown"] is False
    assert out["update"] is True
    assert out["label"] == "Panel 2"
    assert out["snapshotLabels"] == ["Panel 2"]
    assert out["afterUnregister"] == 0
    assert out["reRegister"] is True
    # The grant dropped out of the state file while the plugin stayed
    # enabled: the record is gone and a fresh registration is refused.
    assert out.get("revoked") is True, f"revocation never happened: {out}"
    assert out["reRegisterWithoutGrant"] is False
