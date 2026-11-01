"""The bar's agent popout shows each session's tracked status.

Sessions come from AgentEvents' fold of the event log, so a turn waiting
on the user reads "waiting", a compaction reads "compacting", and an
ended session drops out. When a harness's process is gone but sessions
are still open, AgentProviders writes a session_end with end reason
process_exit for each, once.
"""
import json
import os
import shutil
from pathlib import Path

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

    Timer {
        id: poll
        interval: 100; running: true; repeat: true
        onTriggered: {
            root.ticks++;
            if (AgentEvents.sessions.length < 4 && root.ticks < 40)
                return;
            poll.stop();
            const live = AgentProviders.liveSessionsOf("claude");
            root.result.live = live.map(s => [s.id, s.status]).sort();
            root.result.count = AgentProviders.sessionCountOf("claude");
            root.result.ampCount = AgentProviders.sessionCountOf("amp");
            AgentProviders._reconcilePgrepCount("claude", 2);
            root.result.sentWhileRunning = Object.keys(AgentProviders._endSent).length;
            AgentProviders._reconcilePgrepCount("claude", 0);
            AgentProviders._reconcilePgrepCount("claude", 0);
            root.result.sent = Object.keys(AgentProviders._endSent).sort();
            exitWait.start();
        }
    }

    Timer {
        id: exitWait
        interval: 1500
        onTriggered: {
            console.log("AGENT_STATES " + JSON.stringify(root.result));
            Qt.quit();
        }
    }
}
"""


def _event(sid, event, status, t, **extra):
    return json.dumps({"v": 2, "harness": "claude", "sessionId": sid, "event": event,
                       "status": status, "t": t, **extra})


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_popout_states_and_process_exit_end(tmp_path):
    _seed(tmp_path, plugin_names=("claude-hooks",), dropins=("amp.toml",))
    state = tmp_path / "home/.local/state/aphotic"
    lines = [
        _event("s-run", "turn", "running", 1000),
        _event("s-wait", "turn", "waiting", 1001),
        _event("s-compact", "turn", "compacting", 1002),
        _event("s-done", "turn", "running", 1003),
        _event("s-done", "session_end", "idle", 1004),
    ]
    (state / "agent-events.jsonl").write_text("\n".join(lines) + "\n")

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    calls = tmp_path / "emit-calls.txt"
    fake = bin_dir / "aphotic"
    fake.write_text(f'#!/bin/sh\necho "$*" >> {calls}\n')
    fake.chmod(0o755)

    out = run_probe(tmp_path, PROBE, marker="AGENT_STATES", prefix="_agent_states_",
                    extra_env={"PATH": f"{bin_dir}:{os.environ['PATH']}"})

    assert out["live"] == [["s-compact", "compacting"], ["s-run", "running"],
                           ["s-wait", "waiting"]], out
    assert out["count"] == 3, out
    assert out["ampCount"] == 0, out
    assert out["sentWhileRunning"] == 0, out
    assert out["sent"] == ["s-compact", "s-run", "s-wait"], out

    emitted = sorted(Path(calls).read_text().splitlines())
    assert emitted == [
        f"agent emit session_end --harness claude --session {sid} --end-reason process_exit"
        for sid in ("s-compact", "s-run", "s-wait")
    ], emitted
