"""The Sonar session against the real Quickshell runtime, offscreen.

Proves the activation/teardown contract the design demands: refusal
while disabled or while a blocking prompt holds input, restart instead
of stacking, the sonar surface flag tracked and cleared through
Surfaces, dismissal by an ordinary surface opening, and a teardown that
leaves nothing running.

HYPRLAND_INSTANCE_SIGNATURE is removed so the probe's hyprctl calls
cannot touch the live session: the cursor query exercises its fallback
and the shortcut stays unbound. Windows mount against Qt's offscreen
screen and map nowhere.
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

PROBE = """import QtQuick
import Quickshell
import qs.services

ShellRoot {
    id: root

    // Mirrors ScreenState's contract: the flag flips, ScreenState reports
    // the change into Surfaces.
    QtObject {
        id: fakeState

        property bool sonar: false
        property var surfaceStack: []
        onSonarChanged: Surfaces.track(fakeState, "sonar", fakeState.sonar)
    }

    property var state: fakeState
    property var results: ({})
    property bool done: false
    property int phase: 0

    function finish() {
        if (root.done)
            return;
        root.done = true;
        console.log("SONAR_SESSION " + JSON.stringify(root.results));
        Qt.quit();
    }

    Timer {
        interval: 50
        running: !root.done
        repeat: true
        onTriggered: {
            if (root.phase === 0) {
                root.phase = 1;
                Sonar.ping(root.state);
                root.results.disabledRefused = !Sonar.active;
                root.results.disabledActionAbsent = !Actions.has("sonar.ping");
                Settings.sonarEnabled = true;
            } else if (root.phase === 1) {
                root.phase = 2;
                Actions.invoke("sonar.ping", {screenState: root.state});
            } else if (root.phase === 2) {
                root.phase = 3;
                root.results.activated = Sonar.active;
                root.results.enabledActionPresent = Actions.has("sonar.ping");
                root.results.tracked = root.state.sonar === true;
                root.results.bindCheckFailedClosed = !Sonar.bindWanted;
                root.results.inStack = root.state.surfaceStack.includes("sonar");
                root.results.fallbackOrigin = Sonar.origin !== null;
                Sonar.ping(root.state);
            } else if (root.phase === 3) {
                root.phase = 4;
                root.results.restarted = Sonar.active && root.state.sonar === true;
                Sonar.dismiss();
            } else if (root.phase === 4) {
                root.phase = 5;
                root.results.dismissed = !Sonar.active && root.state.sonar === false;
                Sonar.dismiss();
                root.results.dismissIdempotent = !Sonar.active;
                Surfaces.hold("probe-modal");
                Sonar.ping(root.state);
                root.results.blockedRefused = !Sonar.active;
                Surfaces.release("probe-modal");
            } else if (root.phase === 5) {
                root.phase = 6;
                Sonar.ping(root.state);
            } else if (root.phase === 6) {
                root.phase = 7;
                root.results.reactivated = Sonar.active;
                // An ordinary surface opening on the session screen ends
                // the ping: the transition closes the flag and the
                // session tears down with it.
                Surfaces.track(root.state, "launcher", true);
            } else if (root.phase === 7) {
                root.phase = 8;
                root.results.supersededBySurface = !Sonar.active && root.state.sonar === false;
                Settings.sonarEnabled = false;
                Sonar.ping(root.state);
                root.results.disableRefused = !Sonar.active;
                Settings.sonarEnabled = true;
                Sonar.ping(root.state);
                Settings.sonarEnabled = false;
            } else if (root.phase === 8) {
                root.phase = 9;
                root.results.pendingDisableCancelled = !Sonar.active;
                Settings.sonarEnabled = true;
                Sonar.ping(root.state);
                Surfaces.hold("pending-modal");
            } else if (root.phase === 9) {
                root.phase = 10;
                root.results.pendingBlockCancelled = !Sonar.active;
                Surfaces.release("pending-modal");
                Sonar.ping(root.state);
            } else if (root.phase === 10) {
                if (Sonar.active)
                    return;
                root.results.expired = root.state.sonar === false && Sonar.targets.length === 0;
                root.finish();
            }
        }
    }

    Timer {
        interval: 8000
        running: !root.done
        onTriggered: {
            root.results.timeout = true;
            root.finish();
        }
    }
}
"""


def run_probe(tmp_path: Path, probe_text=PROBE, extra_env=None) -> dict:
    home = tmp_path / "home"
    (home / "runtime").mkdir(mode=0o700, parents=True)
    probe = tempfile.NamedTemporaryFile(
        mode="w", suffix=".qml", prefix="_sonar_session_",
        dir=QML_ROOT, delete=False,
    )
    try:
        probe.write(probe_text)
        probe.close()
        env = os.environ.copy()
        # Never touch the live session: no compositor keyword writes, no
        # real cursor query.
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        env["HOME"] = str(home)
        env["XDG_CACHE_HOME"] = str(home / ".cache")
        env["XDG_DATA_HOME"] = str(home / ".local/share")
        env["XDG_RUNTIME_DIR"] = str(home / "runtime")
        env["QT_QPA_PLATFORM"] = "offscreen"
        env["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=" + str(home / "runtime/unused.sock")
        env.update(extra_env or {})
        result = subprocess.run(
            ["timeout", "20", "qs", "-p", Path(probe.name).name],
            cwd=QML_ROOT, env=env, capture_output=True, text=True, check=False,
        )
    finally:
        Path(probe.name).unlink(missing_ok=True)

    raw = result.stdout + "\n" + result.stderr
    lines = [l.split("SONAR_SESSION ", 1)[1]
             for l in raw.splitlines() if "SONAR_SESSION " in l]
    assert lines, (
        "probe never reported\n"
        f"qs exited {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return json.loads(lines[-1])


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_sonar_session_lifecycle(tmp_path):
    out = run_probe(tmp_path)

    assert not out.get("timeout"), f"probe timed out: {out}"
    assert out["disabledRefused"] is True
    assert out["disabledActionAbsent"] is True
    assert out["enabledActionPresent"] is True
    assert out["activated"] is True
    assert out["tracked"] is True
    assert out["inStack"] is True
    assert out["fallbackOrigin"] is True
    assert out["restarted"] is True
    assert out["dismissed"] is True
    assert out["dismissIdempotent"] is True
    assert out["blockedRefused"] is True
    assert out["reactivated"] is True
    assert out["supersededBySurface"] is True
    assert out["disableRefused"] is True
    assert out["bindCheckFailedClosed"] is True
    assert out["pendingDisableCancelled"] is True
    assert out["pendingBlockCancelled"] is True
    assert out["expired"] is True


HOST_PROBE = """import QtQuick
import Quickshell
import qs.services

ShellRoot {
    id: root

    QtObject {
        id: fakeState

        property bool sonar: false
        property var surfaceStack: []
        onSonarChanged: Surfaces.track(fakeState, "sonar", fakeState.sonar)
    }

    property var state: fakeState
    property var results: ({})
    property bool done: false
    property int phase: 0

    QtObject {
        id: target
        function snapshot() {
            return {id: "core:probe", label: "Probe target", shortcut: "Click", output: Quickshell.screens[0].name,
                rect: {x: Quickshell.screens[0].width / 2 - 10, y: Quickshell.screens[0].height / 2 - 10, width: 100, height: 40}};
        }
        Component.onCompleted: EchoRegistry.attach(target)
        Component.onDestruction: EchoRegistry.detach(target)
    }

    Loader {
        id: hostLoader

        active: false
        source: "modules/sonar/SonarHost.qml"
    }

    function finish() {
        if (root.done)
            return;
        root.done = true;
        console.log("SONAR_HOST " + JSON.stringify(root.results));
        Qt.quit();
    }

    Timer {
        interval: 50
        running: !root.done
        repeat: true
        onTriggered: {
            if (root.phase === 0) {
                root.phase = 1;
                Settings.sonarEnabled = true;
                Sonar.ping(root.state);
            } else if (root.phase === 1) {
                root.phase = 2;
                hostLoader.active = true;
            } else if (root.phase === 2) {
                root.phase = 3;
                // The host must come up clean during a live ping: one
                // overlay window per output, content instantiated.
                root.results.hostLoaded = hostLoader.item !== null;
                root.results.windows = hostLoader.item?.windows?.length ?? 0;
                const window = hostLoader.item?.windows?.[0];
                root.results.targetAnswered = window?.contentItem.children[0].answered.some(t => t.id === "core:probe") === true;
                root.results.contentSized = window && window.contentItem.children[0].width === window.width
                    && window.contentItem.children[0].height === window.height;
                root.results.active = Sonar.active;
            } else if (root.phase === 3) {
                root.phase = 4;
                Sonar.dismiss();

            } else if (root.phase === 4) {
                root.results.unloaded = hostLoader.item?.windows?.length === 0;
                root.results.sessionOver = !Sonar.active;
                root.finish();
            }
        }
    }

    Timer {
        interval: 8000
        running: !root.done
        onTriggered: {
            root.results.timeout = true;
            root.finish();
        }
    }
}
"""


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_sonar_host_mounts_cleanly_during_a_ping(tmp_path):
    if os.environ.get("SONAR_TEST_PLATFORM") != "wayland":
        pytest.skip("PanelWindow requires Wayland; run on the disposable dev VM with SONAR_TEST_PLATFORM=wayland")
    home = tmp_path / "home"
    (home / "runtime").mkdir(mode=0o700, parents=True)
    probe = tempfile.NamedTemporaryFile(
        mode="w", suffix=".qml", prefix="_sonar_host_",
        dir=QML_ROOT, delete=False,
    )
    try:
        probe.write(HOST_PROBE)
        probe.close()
        env = os.environ.copy()
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        env["HOME"] = str(home)
        env["XDG_CACHE_HOME"] = str(home / ".cache")
        env["XDG_DATA_HOME"] = str(home / ".local/share")
        env["XDG_RUNTIME_DIR"] = str(home / "runtime")
        env["QT_QPA_PLATFORM"] = "wayland"
        result = subprocess.run(
            ["timeout", "20", "qs", "-p", Path(probe.name).name],
            cwd=QML_ROOT, env=env, capture_output=True, text=True, check=False,
        )
    finally:
        Path(probe.name).unlink(missing_ok=True)

    raw = result.stdout + "\n" + result.stderr
    lines = [l.split("SONAR_HOST ", 1)[1]
             for l in raw.splitlines() if "SONAR_HOST " in l]
    assert lines, (
        "probe never reported\n"
        f"qs exited {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    out = json.loads(lines[-1])

    assert not out.get("timeout"), f"probe timed out: {out}"
    assert out["hostLoaded"] is True, raw
    assert out["active"] is True
    assert out["windows"] >= 1, "no overlay window instantiated for the output"
    assert out["contentSized"] is True
    assert out["targetAnswered"] is True
    assert out["unloaded"] is True
    assert out["sessionOver"] is True
    for error_line in raw.splitlines():
        lowered = error_line.lower()
        if any(name in lowered for name in ("sonarhost", "sonarwindow", "sonaroverlay")):
            assert "error" not in lowered and "warn" not in lowered, error_line


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_sonar_settings_page_instantiates(tmp_path):
    out = run_probe(tmp_path, """import QtQuick
import Quickshell
import qs.components
import qs.modules.settings
ShellRoot {
    function hasPane(item) {
        if (String(item).startsWith("SonarPane_")) return true;
        return Array.from(item.children ?? []).some(child => hasPane(child));
    }
    ScreenState { id: state; modelData: Quickshell.screens[0] }
    SettingsPanel { id: panel; screenState: state; currentCategory: "sonar" }
    Timer { interval: 300; running: true; onTriggered: {
        console.log("SONAR_SESSION " + JSON.stringify({loaded: hasPane(panel)}));
        Qt.quit();
    }}
}""")
    assert out == {"loaded": True}
