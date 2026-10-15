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
        "zeta": {"capabilities": ["keybind"], "actions": [_action("solo", "")],
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
    elif args == ['test-clear']:
        # The user's bind goes away without a compositor reload.
        state['binds'] = []
        state['events'].append('clear')
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


def _bind_env(tmp_path, registry, prebound, user_bind=None):
    stub = tmp_path / "bin"
    stub.mkdir(exist_ok=True)
    (stub / "hyprctl").write_text(STUB)
    (stub / "hyprctl").chmod(0o755)
    state = tmp_path / "binds.json"
    if user_bind is None:
        user_bind = {"key": "r", "modmask": 65, "mouse": False, "description": "User shortcut",
                     "dispatcher": "exec", "arg": "user-command"}
    binds = [user_bind] if prebound else []
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
def test_a_bind_to_an_action_that_does_not_resolve_is_not_registered(tmp_path):
    # A registry entry naming an action the plugin does not declare binds
    # nothing, so it must not hold its combo either: the combo it claimed
    # is the one a plugin whose action does resolve would have bound. The
    # worker's Actions.has is the same last word, one level down.
    registry = {"acme": _acme(actions=[_action("reload", "Reload Acme")],
                              keybinds=[_bind("SUPER + SHIFT + R", "ghost", "Ghost")])}
    env, state = _bind_env(tmp_path, registry, False)
    out = run_probe(tmp_path, WANTED_PROBE, env)
    data = json.loads(state.read_text())

    assert not out.get("timeout"), out
    assert out["registered"] == 0, out
    assert data["events"] == [], data
    assert data["binds"] == [], data


DERIVE_PROBE = """import QtQuick
import Quickshell
import qs.services
ShellRoot {
    PluginKeybind { id: spaced; combo: "SUPER + SHIFT + R"; command: "c"; description: "d"; wanted: false }
    PluginKeybind { id: bare; combo: "XF86AudioMute"; command: "c"; description: "d"; wanted: false }
    PluginKeybind { id: tight; combo: "SUPER+SHIFT+R"; command: "c"; description: "d"; wanted: false }
    PluginKeybind { id: extra; combo: "SUPER + SHIFT + R + X"; command: "c"; description: "d"; wanted: false }
    Timer {
        interval: 100; running: true
        onTriggered: {
            console.log("SONAR_SESSION " + JSON.stringify({spaced: spaced.legacyCombo, bare: bare.legacyCombo,
                tight: tight.legacyCombo, extra: extra.legacyCombo, extraIssue: extra._comboIssue}));
            Qt.quit();
        }
    }
}
"""


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_legacy_combo_is_derived_from_the_declared_one(tmp_path):
    # The manifest declares one combo. The legacy parser wants the key after
    # a comma and the modifiers space-separated, and a modless bind keeps
    # that modifiers field empty -- passing the key through as it stands, as
    # a bare XF86 key used to, reads the key itself as a modifier.
    #
    # A combo with no legacy form and no modmask is refused rather than
    # derived: deriving it bound a string Hyprland rejects, under a modmask
    # that matched nothing in the live bind table.
    assert run_probe(tmp_path, DERIVE_PROBE) == {
        "spaced": "SUPER SHIFT, R",
        "bare": ", XF86AudioMute",
        "tight": "SUPER SHIFT, R",
        "extra": "",
        "extraIssue": "'R' is not a modifier both parsers know",
    }


# --- the combo as the registry identifies it ----------------------------
#
# The dedupe decides which of two plugins on one combo gets it, so it has
# to see the combo the way the conflict check does, and it has to refuse the
# ones nothing can bind rather than hold them.

COMBOS_PROBE = """import QtQuick
import Quickshell
import qs.services
ShellRoot {
    id: root
    property var result: ({})
    property bool ready: PluginRegistry.isInstalled("alpha")

    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (!root.ready) return;
            root.result.ids = PluginRegistry.keybindRegistrations.map(r => r.id);
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


def _plugin(action, combo, description=""):
    return {"capabilities": ["keybind"], "actions": [_action(action, action)],
            "keybinds": [_bind(combo, action, description)]}


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_a_combo_a_plugin_cannot_bind_does_not_hold_it(tmp_path):
    # A keybind whose action the plugin does not declare binds nothing, so
    # it must not claim the combo either: that takes the key away from the
    # plugin whose action does resolve.
    installed = {
        "alpha": {"capabilities": ["keybind"], "actions": [],
                  "keybinds": [_bind("SUPER + SHIFT + R", "ghost", "Ghost")]},
        "beta": _plugin("ping", "SUPER + SHIFT + R"),
    }
    _seed(tmp_path, installed)
    out = run_probe(tmp_path, COMBOS_PROBE)

    assert not out.get("timeout"), out
    assert out["ids"] == ["beta.ping"], out


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_two_spellings_of_one_combo_are_one_combo(tmp_path):
    # Same modifier bit, same key, two spellings: to the bind table these
    # are one combo, so asserting both left one action unreachable.
    installed = {
        "alpha": _plugin("reload", "SUPER + shift + R"),
        "beta": _plugin("ping", "MOD4 + SHIFT + r"),
    }
    _seed(tmp_path, installed)
    out = run_probe(tmp_path, COMBOS_PROBE)

    assert not out.get("timeout"), out
    assert out["ids"] == ["alpha.reload"], out


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_a_combo_named_after_an_object_prototype_member_still_binds(tmp_path):
    # The dedupe keys on the combo, so the combo cannot be a name that an
    # ordinary object answers for itself.
    installed = {
        "alpha": _plugin("reload", "constructor"),
        "beta": _plugin("ping", "toString"),
    }
    _seed(tmp_path, installed)
    out = run_probe(tmp_path, COMBOS_PROBE)

    assert not out.get("timeout"), out
    assert out["ids"] == ["alpha.reload", "beta.ping"], out


# --- a manifest value is text, not syntax -------------------------------
#
# A plugin.toml is third-party input and the assert is one shell line, so
# each of these proves the marker file stays absent: the value is quoted on
# the way in, not read as shell syntax on the way out.

MARKER_PROBE = WANTED_PROBE


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_a_hostile_description_is_bound_as_text_not_run(tmp_path):
    marker = tmp_path / "description-pwned"
    hostile = 'Reload"; /usr/bin/touch ' + str(marker) + '; echo "'
    env, state = _bind_env(tmp_path, {"acme": _acme(keybinds=[_bind("SUPER + SHIFT + R", "reload", hostile)])}, False)
    out = run_probe(tmp_path, MARKER_PROBE, env)
    data = json.loads(state.read_text())

    assert not out.get("timeout"), out
    assert out["registered"] == 1, out
    assert not marker.exists(), "the description ran as shell syntax on shell start"
    assert data["last"]["description"] == hostile, data


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_a_hostile_action_id_is_bound_as_text_not_run(tmp_path):
    marker = tmp_path / "action-pwned"
    action_id = "reload$(/usr/bin/touch " + str(marker) + ")"
    registry = {"acme": _acme(actions=[_action(action_id, "Reload")],
                              keybinds=[_bind("SUPER + SHIFT + R", action_id, "Reload")])}
    env, state = _bind_env(tmp_path, registry, False)
    out = run_probe(tmp_path, MARKER_PROBE, env)
    data = json.loads(state.read_text())

    assert not out.get("timeout"), out
    assert out["registered"] == 1, out
    assert not marker.exists(), "the action id ran as shell syntax on shell start"
    assert data["last"]["arg"].endswith(f"action acme.{action_id}"), data


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_a_hostile_combo_is_refused_rather_than_bound(tmp_path):
    marker = tmp_path / "combo-pwned"
    combo = "SUPER + SHIFT + $(/usr/bin/touch " + str(marker) + ")"
    env, state = _bind_env(tmp_path, {"acme": _acme(keybinds=[_bind(combo, "reload", "Reload Acme")])}, False)
    out = run_probe(tmp_path, MARKER_PROBE, env)
    data = json.loads(state.read_text())

    assert not out.get("timeout"), out
    assert out["registered"] == 0, out
    assert not marker.exists(), "the combo ran as shell syntax on shell start"
    assert data["events"] == [], data
    assert data["binds"] == [], data


# --- the conflict check has to see the combo the user bound -------------

@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
@pytest.mark.parametrize("combo,modmask", [("CAPS + R", 2), ("MOD2 + R", 16), ("MOD4 + R", 64)])
def test_a_modifier_spelled_the_legacy_way_still_sees_the_user_bind(tmp_path, combo, modmask):
    # `hyprctl binds -j` reports a modmask, so a combo whose modifier had no
    # bit matched no live bind, reported no conflict, and cleared the bind
    # the user had on the combo. The names Hyprland's parsers share all map
    # to a bit now; the ones outside that set are refused outright (see
    # tests/test_plugin_keybind_core.cjs).
    user = {"key": "r", "modmask": modmask, "mouse": False, "description": "User shortcut",
            "dispatcher": "exec", "arg": "user-command"}
    env, state = _bind_env(tmp_path, {"acme": _acme(keybinds=[_bind(combo, "reload", "Reload Acme")])}, True, user)
    out = run_probe(tmp_path, WANTED_PROBE, env)
    data = json.loads(state.read_text())

    assert not out.get("timeout"), out
    assert out["registered"] == 1, out
    assert data["events"] == [], (data["events"], data)
    assert [b["arg"] for b in data["binds"]] == ["user-command"], data


HEAL_PROBE = _probe(LOADED + """
else if (root.phase === 3) {
    // The user's bind goes out of band: no compositor reload fires, so the
    // next read of the bind table is what re-checks the combo.
    root.phase = 4;
    Quickshell.execDetached(["hyprctl", "test-clear"]);
} else if (root.phase === 6) {
    root.phase = 7;
    HyprKeybinds.refresh();
} else if (root.phase === 12) {
    root.phase = 13;
    console.log("SONAR_SESSION " + JSON.stringify(root.result));
    Qt.quit();
} else {
    root.phase++;
}
""")


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_a_combo_freed_after_a_conflict_is_bound_again(tmp_path):
    env, state = _bind_env(tmp_path, {"acme": _acme()}, True)
    out = run_probe(tmp_path, HEAL_PROBE, env)
    data = json.loads(state.read_text())

    assert not out.get("timeout"), out
    assert out["registered"] == 1, out
    events = [e for e in data["events"] if e != "eval"]
    assert events == ["clear", "unbind:r", "bind:r"], (events, data)
    assert data["last"]["description"] == "Reload Acme", data
