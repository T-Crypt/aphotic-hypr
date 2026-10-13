"""Plugin keybinds: the registry entry, and the bind a plugin's combo makes.

Manifest v3.11's `keybind` capability. The registry half seeds
plugins.json and reads PluginRegistry; the worker half drives a stub
`hyprctl` on PATH and asserts the recorded bind-table events, the way
tests/test_sonar_shortcuts.py does. The probe harness removes
HYPRLAND_INSTANCE_SIGNATURE, so no real compositor is ever touched.
"""
import json
import os
import shutil
from pathlib import Path

import pytest
from test_sonar_session import run_probe


def _seed(tmp_path, installed, disabled=None):
    state = tmp_path / "home/.local/state/aphotic"
    state.mkdir(parents=True, exist_ok=True)
    (state / "plugins.json").write_text(json.dumps({"installed": installed, "disabled": disabled or []}))
    profile = tmp_path / "home/Aphotic-Hypr"
    profile.mkdir(parents=True, exist_ok=True)
    # Known, with no layers: the gates answer from the profile rather than
    # from "unknown means enabled", so a requires_layer case is testable.
    (profile / "aphotic.toml").write_text('profile = "base"\nlayers = []\n')


def _bind(combo, action, description="", layer="", data=""):
    return {"action": action, "combo": combo, "description": description,
            "requires_layer": layer, "requires_data": data}


def _action(action_id, label):
    return {"id": action_id, "icon": "", "label": label, "component": "qml/A.qml",
            "requires_layer": "", "requires_data": ""}


def _acme(actions=None, keybinds=None):
    return {"capabilities": ["action", "keybind"],
            "actions": actions if actions is not None else [_action("reload", "Reload Acme")],
            "keybinds": keybinds if keybinds is not None else [_bind("SUPER + SHIFT + R", "reload", "Reload Acme")]}


# --- the registry -------------------------------------------------------

REGISTRY_PROBE = """import QtQuick
import Quickshell
import qs.services
ShellRoot {
    id: root
    property var result: ({})
    property int phase: 0
    property bool ready: PluginRegistry.isInstalled("alpha")

    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (!root.ready) return;
            if (root.phase === 0) {
                root.phase = 1;
                const regs = PluginRegistry.keybindRegistrations;
                root.result.ids = regs.map(r => r.id);
                root.result.alpha = regs.find(r => r.id === "alpha.reload") ?? null;
                root.result.zeta = regs.find(r => r.id === "zeta.solo") ?? null;
                root.result.betaAbsent = !regs.some(r => r.plugin === "beta");
                root.result.gammaAbsent = !regs.some(r => r.plugin === "gamma");
                root.result.deltaAbsent = !regs.some(r => r.plugin === "delta");
                root.result.epsilonAbsent = !regs.some(r => r.plugin === "epsilon");
                root.result.singletonMatches = PluginKeybinds.bindings.length === regs.length;
                SafeMode.active = true;
            } else {
                root.result.safeModeEmpty = PluginRegistry.keybindRegistrations.length === 0
                    && PluginKeybinds.bindings.length === 0;
                console.log("SONAR_SESSION " + JSON.stringify(root.result));
                Qt.quit();
            }
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
def test_keybind_registrations_follow_the_plugin_state(tmp_path):
    installed = {
        "alpha": {"capabilities": ["action", "keybind"],
                  "actions": [_action("reload", "Reload Acme")],
                  "keybinds": [_bind("SUPER + SHIFT + R", "reload", "Reload Acme")]},
        "beta": {"capabilities": ["keybind"],
                 "actions": [_action("ping", "Ping Acme")],
                 "keybinds": [_bind("SUPER + SHIFT + R", "ping")]},
        "gamma": {"capabilities": ["keybind"],
                  "actions": [_action("off", "Off")],
                  "keybinds": [_bind("SUPER + SHIFT + G", "off")]},
        "delta": {"capabilities": ["keybind"],
                  "actions": [_action("gated", "Gated")],
                  "keybinds": [_bind("SUPER + SHIFT + D", "gated", layer="gaming")]},
        "epsilon": {"capabilities": ["keybind"],
                    "actions": [_action("unknown", "Unknown")],
                    "keybinds": [_bind("SUPER + SHIFT + E", "unknown", data="nonsense")]},
        "zeta": {"capabilities": ["keybind"], "actions": [],
                 "keybinds": [_bind("SUPER + SHIFT + Z", "solo")]},
    }
    _seed(tmp_path, installed, disabled=["gamma"])
    out = run_probe(tmp_path, REGISTRY_PROBE)

    assert not out.get("timeout"), out
    # Registry order, one entry per plugin that can actually hold its combo.
    assert out["ids"] == ["alpha.reload", "zeta.solo"], out
    assert out["alpha"]["combo"] == "SUPER + SHIFT + R"
    assert out["alpha"]["description"] == "Reload Acme"
    assert out["alpha"]["requiresLayer"] == ""
    # An empty description falls back to the referenced action's label, then
    # to its id when the manifest's action is not there at all.
    assert out["zeta"]["description"] == "solo", out
    assert out["betaAbsent"] is True, "two plugins on one combo: first in registry order wins"
    assert out["gammaAbsent"] is True, "a disabled plugin holds no combo"
    assert out["deltaAbsent"] is True, "a failing requires_layer token drops the bind"
    assert out["epsilonAbsent"] is True, "a failing requires_data token drops the bind"
    assert out["singletonMatches"] is True, out
    assert out["safeModeEmpty"] is True, "safe mode hands out no bindings"


# --- the worker ---------------------------------------------------------
#
# One stub `hyprctl` records what the worker does to the bind table. It
# answers `-j binds`, records `keyword bindd`/`keyword unbind`/`eval`, and
# models a user binding over the combo.

STUB = '''#!/usr/bin/env python3
import fcntl, json, os, sys
from pathlib import Path
p = Path(os.environ['SONAR_BIND_STATE'])
USER = {'key': 'r', 'modmask': 65, 'mouse': False, 'description': 'User shortcut',
        'dispatcher': 'exec', 'arg': 'user-command'}
with p.with_suffix('.lock').open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    state = json.loads(p.read_text())
    args = sys.argv[1:]
    if args in (['-j', 'binds'], ['binds', '-j']):
        print(json.dumps(state['binds']))
    elif args == ['test-conflict']:
        state['binds'] = [USER]
        state['events'].append('conflict')
    elif args[:2] == ['keyword', 'bindd']:
        mods, key, description, dispatcher, command = [s.strip() for s in args[2].split(',', 4)]
        modmask = (64 if 'SUPER' in mods else 0) | (1 if 'SHIFT' in mods else 0)
        state['binds'].append({'key': key.lower(), 'modmask': modmask, 'mouse': False,
                               'description': description, 'has_description': True,
                               'dispatcher': dispatcher, 'arg': command})
        state['last'] = state['binds'][-1]
        state['events'].append('bind:' + key.lower())
    elif args[:2] == ['keyword', 'unbind']:
        key = args[2].split(',')[1].strip().lower()
        state['binds'] = [b for b in state['binds'] if b['key'] != key]
        state['events'].append('unbind:' + key)
    elif args[:1] == ['eval']:
        state['events'].append('eval')
    else:
        print('{}')
    p.write_text(json.dumps(state))
'''

_PROBE_HEAD = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
    id: root
    property var result: ({})
    property int phase: 0

    Process {
        id: control
        onExited: Hypr.configReloaded()
    }

    Timer {
        interval: 250; running: true; repeat: true
        onTriggered: {
            // Some phases below empty the registry on purpose, so the wait
            // for it to load only applies before the first phase runs.
            if (root.phase === 0 && !PluginRegistry.isInstalled("acme")) return;
"""

_PROBE_TAIL = """        }
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


def _probe(phases):
    body = "\n".join(("            " + line) if line.strip() else "" for line in phases.strip("\n").splitlines())
    return _PROBE_HEAD + body + "\n" + _PROBE_TAIL


LOADED = """
if (root.phase === 0) {
    root.phase = 1;
    root.result.registered = PluginKeybinds.bindings.length;
    root.result.id = PluginKeybinds.bindings[0]?.id ?? "";
    root.result.combo = PluginKeybinds.bindings[0]?.combo ?? "";
}
"""


def _bind_env(tmp_path, registry, prebound):
    stub = tmp_path / "bin"
    stub.mkdir(exist_ok=True)
    (stub / "hyprctl").write_text(STUB)
    (stub / "hyprctl").chmod(0o755)
    state = tmp_path / "binds.json"
    binds = [{"key": "r", "modmask": 65, "mouse": False, "description": "User shortcut",
              "dispatcher": "exec", "arg": "user-command"}] if prebound else []
    state.write_text(json.dumps({"binds": binds, "events": []}))
    _seed(tmp_path, registry)
    return {"PATH": str(stub) + os.pathsep + os.environ["PATH"], "SONAR_BIND_STATE": str(state)}, state


YIELD_PROBE = _probe(LOADED + """
else if (root.phase === 4) {
    // By now the check and the assert have run. A user bind takes the
    // combo, and a compositor reload asks the worker to re-check.
    root.phase = 5;
    control.command = ["hyprctl", "test-conflict"];
    control.running = true;
} else if (root.phase === 8) {
    root.phase = 9;
    console.log("SONAR_SESSION " + JSON.stringify(root.result));
    Qt.quit();
} else {
    root.phase++;
}
""")


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
@pytest.mark.parametrize("prebound", [False, True])
def test_plugin_bind_yields_to_a_user_bind_on_the_combo(tmp_path, prebound):
    env, state = _bind_env(tmp_path, {"acme": _acme()}, prebound)
    out = run_probe(tmp_path, YIELD_PROBE, env)
    data = json.loads(state.read_text())

    assert not out.get("timeout"), out
    assert out["registered"] == 1, out
    assert out["id"] == "acme.reload", out
    assert out["combo"] == "SUPER + SHIFT + R", out

    events = [e for e in data["events"] if e != "eval"]
    if prebound:
        # A user bind owns the combo from the start: the worker checks, sees
        # it, and neither clears the tables nor asserts.
        assert events == ["conflict"], (events, data)
        assert "last" not in data, data
    else:
        # Enable: clear both parser tables, then bind. The conflict arrives
        # after, and the reload's re-check leaves the user's bind alone.
        assert events == ["unbind:r", "bind:r", "conflict"], (events, data)
        assert data["last"]["description"] == "Reload Acme", data
        assert "ipc call aphotic action acme.reload" in data["last"]["arg"], data
    # Either way the combo ends up carrying the user's bind and nothing of
    # the plugin's.
    assert [b["arg"] for b in data["binds"]] == ["user-command"], data


REMOVAL_PROBE = _probe(LOADED + """
else if (root.phase === 2) {
    root.phase = 3;
    PluginRegistry._data = {installed: {}, disabled: []};
} else if (root.phase === 6) {
    root.phase = 7;
    root.result.afterRemoval = PluginKeybinds.bindings.length;
    console.log("SONAR_SESSION " + JSON.stringify(root.result));
    Qt.quit();
} else {
    root.phase++;
}
""")


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_plugin_bind_is_removed_when_the_plugin_goes(tmp_path):
    env, state = _bind_env(tmp_path, {"acme": _acme()}, False)
    out = run_probe(tmp_path, REMOVAL_PROBE, env)
    data = json.loads(state.read_text())

    assert not out.get("timeout"), out
    assert out["registered"] == 1, out
    assert out["afterRemoval"] == 0, out
    events = [e for e in data["events"] if e != "eval"]
    assert events == ["unbind:r", "bind:r", "unbind:r"], (events, data)
    assert data["binds"] == [], data


WANTED_PROBE = _probe(LOADED + """
else if (root.phase === 4) {
    root.phase = 5;
    console.log("SONAR_SESSION " + JSON.stringify(root.result));
    Qt.quit();
} else {
    root.phase++;
}
""")


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_a_bind_to_an_action_that_does_not_resolve_never_binds(tmp_path):
    # A registry entry naming an action the plugin does not declare: the
    # registration exists, and Actions.has is the last word on whether the
    # combo is worth holding.
    registry = {"acme": _acme(actions=[_action("reload", "Reload Acme")],
                              keybinds=[_bind("SUPER + SHIFT + R", "ghost", "Ghost")])}
    env, state = _bind_env(tmp_path, registry, False)
    out = run_probe(tmp_path, WANTED_PROBE, env)
    data = json.loads(state.read_text())

    assert not out.get("timeout"), out
    assert out["registered"] == 1, out
    assert data["events"] == [], data
    assert data["binds"] == [], data


DERIVE_PROBE = """import QtQuick
import Quickshell
import qs.services
ShellRoot {
    PluginKeybind { id: spaced; combo: "SUPER + SHIFT + R"; command: "c"; description: "d"; wanted: false }
    PluginKeybind { id: bare; combo: "XF86AudioMute"; command: "c"; description: "d"; wanted: false }
    Timer {
        interval: 100; running: true
        onTriggered: {
            console.log("SONAR_SESSION " + JSON.stringify({spaced: spaced.legacyCombo, bare: bare.legacyCombo}));
            Qt.quit();
        }
    }
}
"""


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_legacy_combo_is_derived_from_the_declared_one(tmp_path):
    # The manifest declares one combo, in the canonical Lua form. The legacy
    # parser wants the key after a comma and the modifiers space-separated.
    assert run_probe(tmp_path, DERIVE_PROBE) == {"spaced": "SUPER SHIFT, R", "bare": "XF86AudioMute"}
