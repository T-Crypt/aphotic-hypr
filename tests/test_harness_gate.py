"""The agent gate answers from descriptors, not from login probes.

Slice 2 of the harness-descriptor design. The probe seeds harnesses.json
the way slice 1's merge writes it (running the real merge into a
throwaway HOME) and then reads the real singletons offscreen: a record
holding one OpenCode descriptor, with no Claude or Codex login probe
passing, makes AgentRoles answer hasConfiguredHarness true; an empty
registry and an absent record answer false; and AgentEvents folds an
untagged record under "unknown" rather than under a named harness.
"""
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest
from test_sonar_session import run_probe

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Configs" / ".local" / "lib" / "aphotic"))
import harnesses_merge

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "harnesses"
NOW = datetime(2026, 10, 17, 9, 30, 0, tzinfo=timezone.utc)

PROBE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.ai
ShellRoot {
    id: root
    property var result: ({})
    property int want: __WANT__
    property int ticks: 0

    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            root.ticks++;
            // want > 0 waits for the record to land; want === 0 has no
            // content to wait for, and [] is the value before the load
            // settles too, so the first tick already answers.
            const settled = want === 0 || Harnesses.harnesses.length === want || root.ticks >= 30;
            if (!settled)
                return;
            root.result.gate = AgentRoles.hasConfiguredHarness;
            root.result.ids = Harnesses.harnesses.map(h => h.id);
            root.result.claudeAvailable = AiProviders.claudeAvailable;
            root.result.codexAvailable = AiProviders.codexAvailable;
            root.result.untagged = AgentEvents.applyTo([], {sessionId: "untagged-1", event: "session_start", t: 123})[0].harness;
            console.log("HARNESS_GATE " + JSON.stringify(root.result));
            Qt.quit();
        }
    }

    Timer {
        interval: 8000; running: true
        onTriggered: {
            root.result.timeout = true;
            console.log("HARNESS_GATE " + JSON.stringify(root.result));
            Qt.quit();
        }
    }
}
"""


def _probe(want: int) -> str:
    return PROBE.replace("__WANT__", str(want))


def _seed(tmp_path: Path, plugin_names=(), dropins=()) -> None:
    """Run the real merge into the probe's throwaway HOME, the way a
    machine with these plugins installed would carry its record."""
    state = tmp_path / "home/.local/state/aphotic"
    state.mkdir(parents=True, exist_ok=True)
    config = tmp_path / "config"
    (config / harnesses_merge.DROPIN_DIR_NAME).mkdir(parents=True, exist_ok=True)
    plugins = tmp_path / "plugins"
    for name in plugin_names:
        (plugins / name).mkdir(parents=True, exist_ok=True)
        (plugins / name / "plugin.toml").write_text(
            (FIXTURES / "plugins" / name / "plugin.toml").read_text(encoding="utf-8"),
            encoding="utf-8",
        )
    for name in dropins:
        (config / harnesses_merge.DROPIN_DIR_NAME / name).write_text(
            (FIXTURES / "dropins" / name).read_text(encoding="utf-8"),
            encoding="utf-8",
        )
    (state / harnesses_merge.PLUGINS_STATE_NAME).write_text(
        json.dumps({"installed": {name: {} for name in plugin_names}, "disabled": []}),
        encoding="utf-8",
    )
    # The layer gates answer off the profile rather than off "unknown
    # means enabled", with no layers: the probe comes up with the ai
    # layer off, so no login probe, poll or reconcile runs inside it.
    profile = tmp_path / "home/Aphotic-Hypr"
    profile.mkdir(parents=True, exist_ok=True)
    (profile / "aphotic.toml").write_text('profile = "base"\nlayers = []\n')
    harnesses_merge.merge(config, plugins, state, now=NOW)


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_an_opencode_only_record_opens_the_gate(tmp_path):
    # Only opencode-hooks is installed: no Claude or Codex login probe can
    # pass in this HOME, so the old gate would have answered false here.
    _seed(tmp_path, plugin_names=("opencode-hooks",))
    out = run_probe(tmp_path, _probe(1), marker="HARNESS_GATE", prefix="_harness_gate_")

    assert not out.get("timeout"), out
    assert out["ids"] == ["opencode"], out
    assert out["claudeAvailable"] is False, out
    assert out["codexAvailable"] is False, out
    assert out["gate"] is True, out
    assert out["untagged"] == "unknown", out


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_a_drop_in_record_opens_the_gate(tmp_path):
    # A custom harness with no hook plugin of its own: the drop-in alone
    # is the opt-in, and the gate opens for it too.
    _seed(tmp_path, dropins=("amp.toml",))
    out = run_probe(tmp_path, _probe(1), marker="HARNESS_GATE", prefix="_harness_gate_")

    assert not out.get("timeout"), out
    assert out["ids"] == ["amp"], out
    assert out["gate"] is True, out


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_an_empty_registry_keeps_the_gate_closed(tmp_path):
    # No harness-hook plugins and no drop-ins: the merge writes an empty
    # list, every consumer sees one shape, and the gate stays off.
    _seed(tmp_path)
    out = run_probe(tmp_path, _probe(0), marker="HARNESS_GATE", prefix="_harness_gate_")

    assert not out.get("timeout"), out
    assert out["ids"] == [], out
    assert out["gate"] is False, out
    assert out["untagged"] == "unknown", out


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_an_absent_record_keeps_the_gate_closed(tmp_path):
    # First boot before the first merge: the file does not exist yet, the
    # singleton keeps its empty record, and nothing revalidates it.
    (tmp_path / "home/.local/state/aphotic").mkdir(parents=True)
    out = run_probe(tmp_path, _probe(0), marker="HARNESS_GATE", prefix="_harness_gate_")

    assert not out.get("timeout"), out
    assert out["ids"] == [], out
    assert out["gate"] is False, out
