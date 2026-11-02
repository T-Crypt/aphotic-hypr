"""A harness that is open with no live turn shows as open, not absent.

AgentProviders samples harness processes once a minute. A harness whose
process runs while it has no live session in the event log is listed in
`openIdle`: one with only ended sessions, and one whose hook never fired.
A harness with a live session is not, and a closed one drops out.
"""
import json
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
    Component.onCompleted: AgentEvents.hold("probe", true)

    function ids(): var {
        return AgentProviders.openIdle.map(p => p.id).sort();
    }

    Timer {
        id: poll
        interval: 100; running: true; repeat: true
        onTriggered: {
            root.ticks++;
            if ((AgentEvents.sessions.length < 1 || AgentProviders.providers.length < 2) && root.ticks < 40)
                return;
            poll.stop();
            root.result.before = root.ids();
            AgentProviders._reconcilePgrepCount("claude", 1);
            AgentProviders._reconcilePgrepCount("amp", 1);
            root.result.bothOpen = root.ids();
            root.result.claudeProcesses = AgentProviders.stats[AgentProviders._findIndex("claude")].processCount;
            AgentProviders._reconcilePgrepCount("amp", 0);
            root.result.ampClosed = root.ids();
            console.log("OPEN_IDLE " + JSON.stringify(root.result));
            Qt.quit();
        }
    }
}
"""


def _event(sid, event, status, t):
    return json.dumps({"v": 2, "harness": "claude", "sessionId": sid, "event": event,
                       "status": status, "t": t})


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_open_harness_without_a_live_session_is_open_idle(tmp_path):
    _seed(tmp_path, plugin_names=("claude-hooks",), dropins=("amp.toml",))
    state = tmp_path / "home/.local/state/aphotic"
    lines = [
        _event("s-done", "turn", "running", 1000),
        _event("s-done", "session_end", "idle", 1001),
    ]
    (state / "agent-events.jsonl").write_text("\n".join(lines) + "\n")

    out = run_probe(tmp_path, PROBE, marker="OPEN_IDLE", prefix="_open_idle_")

    assert out["before"] == [], out
    assert out["bothOpen"] == ["amp", "claude"], out
    assert out["claudeProcesses"] == 1, out
    assert out["ampClosed"] == ["claude"], out


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_harness_with_a_live_session_is_not_open_idle(tmp_path):
    _seed(tmp_path, plugin_names=("claude-hooks",), dropins=("amp.toml",))
    state = tmp_path / "home/.local/state/aphotic"
    (state / "agent-events.jsonl").write_text(_event("s-run", "turn", "running", 1000) + "\n")

    out = run_probe(tmp_path, PROBE, marker="OPEN_IDLE", prefix="_open_idle_")

    assert out["bothOpen"] == ["amp"], out
