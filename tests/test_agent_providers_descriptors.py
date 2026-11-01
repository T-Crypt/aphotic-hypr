"""The bar's agent tabs come from harness descriptors, not a table in core.

Slice 3 of the harness-descriptor design. The probe seeds harnesses.json
with the real merge, then reads AgentProviders offscreen: every
descriptor becomes a tab with its own label, icon, process name and
launch command, a drop-in harness gets a tab with no core change, and the
pgrep reconcile counts each named process from one `pgrep -l -x` call.
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
    property int want: __WANT__
    property int ticks: 0

    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            root.ticks++;
            if (AgentProviders.providers.length !== want && root.ticks < 30)
                return;
            root.result.providers = AgentProviders.providers;
            root.result.pattern = AgentProviders._pgrepPattern();
            root.result.targets = AgentProviders._pgrepTargets.map(p => p.id);
            AgentProviders._reconcilePgrepOutput("101 claude\\n102 claude\\n103 amp\\n");
            root.result.counts = AgentProviders.stats.map(s => s.sessionCount);
            console.log("AGENT_PROVIDERS " + JSON.stringify(root.result));
            Qt.quit();
        }
    }
}
"""


def _probe(want: int) -> str:
    return PROBE.replace("__WANT__", str(want))


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_tabs_follow_descriptors_including_a_drop_in(tmp_path):
    _seed(tmp_path, plugin_names=("claude-hooks", "pi-hooks"), dropins=("amp.toml",))
    out = run_probe(tmp_path, _probe(4), marker="AGENT_PROVIDERS", prefix="_agent_providers_")

    by_id = {p["id"]: p for p in out["providers"]}
    assert set(by_id) == {"claude", "pi", "omp", "amp"}, out
    assert by_id["amp"]["label"] == "Amp"
    assert by_id["amp"]["processName"] == "amp"
    assert by_id["amp"]["launchCmd"] == ["amp"]
    assert by_id["claude"]["processName"] == "claude"

    # Pi and OMP have no process name to match, so the reconcile leaves
    # them to their hook events.
    assert set(out["targets"]) == {"claude", "amp"}, out
    assert set(out["pattern"].split("|")) == {"claude", "amp"}, out

    counts = dict(zip([p["id"] for p in out["providers"]], out["counts"]))
    assert counts["claude"] == 2, out
    assert counts["amp"] == 1, out
    assert counts["pi"] == 0, out


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_no_descriptors_means_no_tabs(tmp_path):
    _seed(tmp_path)
    out = run_probe(tmp_path, _probe(0), marker="AGENT_PROVIDERS", prefix="_agent_providers_")

    assert out["providers"] == [], out
    assert out["pattern"] == "", out
