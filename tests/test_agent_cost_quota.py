"""Cost and quota from v2 records reach the bar for any harness.

v2 sends cost as { amount, currency }. AgentEvents sums it per session
and AgentProviders sums it per harness for today, and a harness that never
reports a cost reads null, not zero. Quota windows from a `quota` record
are kept per harness.
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
    Component.onCompleted: {
        root.result.active = AgentProviders.active;
        AgentEvents.hold("probe", true);
    }

    Timer {
        id: poll
        interval: 100; running: true; repeat: true
        onTriggered: {
            root.ticks++;
            if (AgentEvents.sessions.length < 2 && root.ticks < 40)
                return;
            poll.stop();
            const s = AgentEvents.sessions.find(x => x.id === "a1");
            root.result.sessionCost = Math.round(s.cost * 1000) / 1000;
            root.result.sessionCurrency = s.currency;
            const amp = AgentProviders.usageOf("amp");
            root.result.ampCost = Math.round(amp.todayCost * 1000) / 1000;
            root.result.ampTokens = amp.todayTokens;
            root.result.claudeCost = AgentProviders.usageOf("claude").todayCost;
            root.result.ampQuota = AgentProviders.quotaOf("amp");
            console.log("AGENT_COST " + JSON.stringify(root.result));
            Qt.quit();
        }
    }
}
"""


def _rec(harness, sid, event, t, **extra):
    return json.dumps({"v": 2, "harness": harness, "sessionId": sid, "event": event,
                       "status": "running", "t": t, **extra})


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_cost_objects_sum_and_quota_is_per_harness(tmp_path):
    _seed(tmp_path, plugin_names=("claude-hooks",), dropins=("amp.toml",))
    state = tmp_path / "home/.local/state/aphotic"
    lines = [
        _rec("amp", "a1", "usage", 1000, inputTokens=100, outputTokens=20,
             cost={"amount": 0.014, "currency": "USD"}),
        _rec("amp", "a1", "usage", 1001, inputTokens=10, outputTokens=5,
             cost={"amount": 0.002, "currency": "USD"}),
        _rec("amp", "a1", "quota", 1002, quota={"fiveHour": {"usedPercent": 41.0, "resetsAt": 0}}),
        _rec("claude", "c1", "usage", 1003, inputTokens=7, outputTokens=3),
    ]
    (state / "agent-events.jsonl").write_text("\n".join(lines) + "\n")

    out = run_probe(tmp_path, PROBE, marker="AGENT_COST", prefix="_agent_cost_")

    assert out["sessionCost"] == 0.016, out
    assert out["sessionCurrency"] == "USD", out
    assert out["ampCost"] == 0.016, out
    assert out["ampTokens"] == 135, out
    assert out["claudeCost"] is None, out
    assert out["ampQuota"] == {"fiveHour": {"usedPercent": 41.0, "resetsAt": 0}}, out
