"""EngineRegistry: the three sources, the precedence rule, and the warnings.

The registry scans a core engines directory and a drop-in directory, and
merges the engine blocks PluginRegistry reads out of plugins.json. The
offscreen probe seeds all three and asserts the resolved list the way a
consumer would see it: a drop-in on the plugin's id wins and both stay
listed, winner first, with the loser carrying an "overridden by" note; a
malformed descriptor is absent with its exact warning. run_probe gives a
temp HOME and XDG dirs, so nothing here touches the live ~/.config.
"""
import json
import shutil
from pathlib import Path

import pytest
from test_sonar_session import run_probe

from test_plugin_keybinds import _seed as _seed_registry


def _seed(tmp_path, installed, core=None, dropins=None):
    _seed_registry(tmp_path, installed)
    if core is not None:
        core_dir = tmp_path / "dots/Configs/quickshell/aphotic/services/ai/engines"
        core_dir.mkdir(parents=True, exist_ok=True)
        for name, text in core.items():
            (core_dir / name).write_text(text)
    if dropins is not None:
        drop = tmp_path / "home/.config/aphotic/engines"
        drop.mkdir(parents=True, exist_ok=True)
        for name, text in dropins.items():
            (drop / name).write_text(text)
    return tmp_path / "dots"


CORE_DESCRIPTOR = """
[engine]
id = "core-engine"
label = "Core Engine"
protocol = "engine-report"
endpoint = "/.aphotic/engine.json"
default_host = "http://127.0.0.1:9800"
capabilities = ["models"]
"""

DROP_IN = """
[engine]
id = "vega"
label = "Vega (workstation)"
protocol = "engine-report"
endpoint = "/.aphotic/engine.json"
default_host = "http://127.0.0.1:9911"
capabilities = ["models", "claims"]
"""

BAD_DROP_IN = """
[engine]
id = "Bad"
protocol = "engine-report"
endpoint = "/x"
default_host = "http://127.0.0.1:9999"
"""


def _plugin_engine():
    return {
        "capabilities": ["engine"],
        "engine": {
            "id": "vega",
            "label": "Vega",
            "protocol": "engine-report",
            "endpoint": "/.aphotic/engine.json",
            "host_key": "",
            "default_host": "http://10.0.0.9:9911",
            "key": "",
            "process": "vega-server",
            "port_flag": "--port",
            "gateway": "",
            "gateway_entry": "",
            "manages": ["vega-server"],
            "capabilities": ["models", "claims"],
            "control": {"start": "", "stop": "", "load": "", "unload": "", "switch": ""},
            "stats": None,
            "progress": None,
        },
    }


PROBE = """import QtQuick
import Quickshell
import qs.services
import qs.services.ai
ShellRoot {
    id: root
    property var result: ({})
    property bool ready: PluginRegistry.isInstalled("vega-stack")

    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (!root.ready) return;
            if (EngineRegistry.descriptors.length < 3) return;
            root.result.ids = EngineRegistry.descriptors.map(d => d.id);
            root.result.sources = EngineRegistry.descriptors.map(d => d.source);
            root.result.overridden = EngineRegistry.descriptors.map(d => d.overriddenBy);
            root.result.shadowed = EngineRegistry.shadowed.map(s => s.id);
            root.result.warnings = EngineRegistry.warnings;
            root.result.baseUrl = EngineRegistry.baseUrl("vega");
            root.result.canModels = EngineRegistry.can("vega", "models");
            root.result.canProgress = EngineRegistry.can("vega", "progress");
            console.log("SONAR_SESSION " + JSON.stringify(root.result));
            Qt.quit();
        }
    }

    Timer {
        interval: 8000; running: true
        onTriggered: {
            root.result.timeout = true;
            console.log("SONAR_SESSION " + JSON.stringify(root.result));
            Qt.quit();
        }
    }
}
"""


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_engine_registry_resolves_the_three_sources(tmp_path):
    dots = _seed(
        tmp_path,
        {"vega-stack": _plugin_engine()},
        core={"core-engine.toml": CORE_DESCRIPTOR},
        dropins={"vega.toml": DROP_IN, "bad.toml": BAD_DROP_IN},
    )
    out = run_probe(tmp_path, PROBE, {"APHOTIC_DOTS_DIR": str(dots)})

    assert not out.get("timeout"), out
    # Drop-ins first, then the plugin, then core. The shadowed vega stays
    # listed after the drop-in that overrode it, so a Settings row can say
    # so rather than the loser vanishing.
    assert out["ids"] == ["vega", "vega", "core-engine"], out
    assert out["sources"] == ["drop-in", "plugin", "core"], out
    assert out["overridden"][0] == "", out
    assert out["overridden"][1] == "~/.config/aphotic/engines/vega.toml", out
    assert out["overridden"][2] == "", out
    assert out["shadowed"] == ["vega"], out

    assert "aphotic engine: 'vega' from a drop-in shadows plugin 'vega-stack'" in out["warnings"], out
    assert ("aphotic engine: 'Bad' skipped, an engine id must be lowercase, "
            "start with a letter, and use only [a-z0-9-]") in out["warnings"], out

    # The winner answers the consumer calls, not the shadowed plugin.
    assert out["baseUrl"] == "http://127.0.0.1:9911", out
    assert out["canModels"] is True, out
    assert out["canProgress"] is False, out


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_engine_registry_missing_directories_are_empty(tmp_path):
    # A partial install with no core directory and no drop-in directory
    # must read an empty list, not error: the scan fails closed per file,
    # and a directory that does not exist contributes nothing.
    state = tmp_path / "home/.local/state/aphotic"
    state.mkdir(parents=True, exist_ok=True)
    (state / "plugins.json").write_text(json.dumps({"installed": {}, "disabled": []}))
    out = run_probe(tmp_path, """import QtQuick
import Quickshell
import qs.services.ai
ShellRoot {
    id: root
    property var result: ({})
    Timer {
        interval: 400; running: true
        onTriggered: {
            root.result.count = EngineRegistry.descriptors.length;
            root.result.warnings = EngineRegistry.warnings.length;
            console.log("SONAR_SESSION " + JSON.stringify(root.result));
            Qt.quit();
        }
    }
    Timer {
        interval: 8000; running: true
        onTriggered: {
            root.result.timeout = true;
            console.log("SONAR_SESSION " + JSON.stringify(root.result));
            Qt.quit();
        }
    }
}""", {"APHOTIC_DOTS_DIR": str(tmp_path / "dots")})

    assert not out.get("timeout"), out
    assert out["count"] == 0, out
    assert out["warnings"] == 0, out
