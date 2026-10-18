"""EngineStream: a reporting command's engines become claimants under their own names.

A fake reporter prints one gateway report naming two engines and stays up.
One engine id is already registered by another adapter, so the stream must
leave it alone. The probe runs offscreen under a temp HOME.
"""
import shutil

import pytest
from test_sonar_session import run_probe

REPORT = ('{"protocol":"aphotic-engine/1","engine":{"id":"gate"},"engines":['
          '{"id":"expert","label":"Expert","state":"active","cpuPercent":120.5,"threads":20,'
          '"models":[{"name":"big-moe","state":"ready","vramMiB":23896,"ramMiB":46012}]},'
          '{"id":"taken","models":[{"name":"x","vramMiB":100}]}]}')

PROBE = """import QtQuick
import Quickshell
import qs.services
import qs.services.ai
import qs.services.profile
ShellRoot {
    id: root
    property var result: ({})

    Component.onCompleted: ProfileEngine.register({ id: "taken", label: "Someone else" })

    EngineStream {
        id: stream
        descriptor: ({ id: "gate", source: "drop-in", sourceName: "gate.toml", stream: ["STREAM_PATH"] })
    }

    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (EngineRegistry.liveIds.length === 0 || ResourceEngine.claimsOf("expert").length < 2) return;
            root.result.live = EngineRegistry.liveEngines.map(e => ({ id: e.id, label: e.label, cpu: e.cpuPercent, gateway: e.gateway }));
            root.result.expert = ResourceEngine.claimsOf("expert").map(c => c.resource + "=" + c.amount).sort();
            root.result.taken = ResourceEngine.claimsOf("taken").length;
            root.result.takenLabel = ProfileEngine.profiles["taken"].label;
            console.log("SONAR_SESSION " + JSON.stringify(root.result));
            Qt.quit();
        }
    }

    Timer {
        interval: 10000; running: true
        onTriggered: {
            root.result.timeout = true;
            root.result.live = EngineRegistry.liveIds;
            root.result.expert = ResourceEngine.claimsOf("expert").map(c => c.resource + "=" + c.amount);
            console.log("SONAR_SESSION " + JSON.stringify(root.result));
            Qt.quit();
        }
    }
}
"""


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_stream_engines_become_claimants(tmp_path):
    reporter = tmp_path / "reporter.sh"
    reporter.write_text("#!/bin/sh\nprintf '%s\\n' '" + REPORT + "'\nexec sleep 30\n")
    reporter.chmod(0o755)
    out = run_probe(tmp_path, PROBE.replace("STREAM_PATH", str(reporter)))

    assert not out.get("timeout"), out
    assert out["live"] == [{"id": "expert", "label": "Expert", "cpu": 120.5, "gateway": "gate"}], out
    assert out["expert"] == ["gpu-vram=23896", "memory=46012"], out
    assert out["taken"] == 0, out
    assert out["takenLabel"] == "Someone else", out
