"""The phone stack's flags and its device bridge, offscreen.

Flags first: all eight default off on a fresh HOME, and the bridge flag
actually moves when something assigns it, so a later phase proving the
bridge reads a value rather than a constant. Then the save half: each of
the eight flags assigned on its own has to reach settings.json, because
that file is the user's surface for them and a flag that only moves in
memory comes back off at the next boot. Then the bridge itself: what it
spawns and what it parses when the flag is off, when the flag is on with a
stub command on PATH, when the flag arrives true from settings.json, when
the command is not installed at all, and when it is installed and fails.
Then the two ways to ask it again: Phone.refresh() and the Refresh row in
each of the two tiles, including the refusal that keeps a burst of them to
one scan.

A real paired phone is out of reach here. The reachable path is driven with
a stub `kdeconnect-cli` that prints the lines the real one printed when
this was planned and records every call it receives, so these tests prove
the wiring and nothing about the transport.
"""
import json
import os
import shutil
from pathlib import Path

import pytest
from test_sonar_session import run_probe


ROOT = Path(__file__).resolve().parents[1]
QML_ROOT = ROOT / "Configs/quickshell/aphotic"

TEST_PHONE = "aaaaaaaa_bbbb_cccc_dddd_eeeeffff0000"
SECOND_PHONE = "11111111_2222_3333_4444_555566667777"

PHONE_FLAGS = [
    "phoneBridge", "phoneMirror", "phoneCalls", "phoneAlarms",
    "phoneIcons", "phoneCamera", "phoneMic", "phoneLocalSend",
]

FLAGS_PROBE = """import QtQuick
import Quickshell
import qs.config
import qs.services

ShellRoot {
    id: root

    property var result: ({})
    property bool done: false

    function finish(): void {
        if (root.done)
            return;
        root.done = true;
        console.log("PHONE_FLAGS " + JSON.stringify(root.result));
        Qt.quit();
    }

    Timer {
        interval: 50
        running: !root.done
        repeat: true
        onTriggered: {
            root.result.settings = [
                Settings.phoneBridge, Settings.phoneMirror, Settings.phoneCalls, Settings.phoneAlarms,
                Settings.phoneIcons, Settings.phoneCamera, Settings.phoneMic, Settings.phoneLocalSend
            ];
            root.result.config = [
                Config.phone.bridge, Config.phone.mirror, Config.phone.calls, Config.phone.alarms,
                Config.phone.icons, Config.phone.camera, Config.phone.mic, Config.phone.localSend
            ];
            Settings.phoneBridge = true;
            root.result.wired = Settings.phoneBridge === true;
            Settings.phoneBridge = false;
            root.result.restored = Settings.phoneBridge === false;
            root.finish();
        }
    }
}
"""

# One probe per flag, named by PHONE_FLAG, assigning that flag once and
# nothing else. The save writes every key from memory at once, so a run
# that assigned two flags would let one handler's write carry the other's
# value and hide a handler that never fires.
SAVE_PROBE = """import QtQuick
import Quickshell
import qs.services

ShellRoot {
    id: root

    property string flag: Quickshell.env("PHONE_FLAG")
    property bool assigned: false
    property bool assignedBefore: false
    property int tick: 0
    property int assignTick: 0
    property bool done: false

    function finish(): void {
        if (root.done)
            return;
        root.done = true;
        console.log("PHONE_SAVE " + JSON.stringify({
            flag: root.flag,
            loaded: Settings._loaded,
            assigned: root.assigned,
            before: root.assignedBefore,
            value: Settings[root.flag] === true
        }));
        Qt.quit();
    }

    Timer {
        interval: 25
        repeat: true
        running: !root.done
        onTriggered: {
            root.tick++;
            if (!root.assigned) {
                // Settings._saveState() returns early until its file view
                // finishes loading, and the mkdir that makes the state
                // directory runs alongside it.
                if (Settings._loaded && root.tick >= 6) {
                    root.assignedBefore = Settings[root.flag] === true;
                    Settings[root.flag] = true;
                    root.assigned = true;
                    root.assignTick = root.tick;
                } else if (root.tick >= 80) {
                    root.finish();
                }
                return;
            }
            if (root.tick - root.assignTick >= 3)
                root.finish();
        }
    }
}
"""

# One probe for every bridge scenario: PHONE_ENABLE turns the flag on from
# inside, PHONE_SPAWN says a scan is expected, PHONE_SENTINEL parks
# toolPresent on true first, PHONE_REFRESH_WHILE_OFF calls refresh() with
# the flag off. One probe means the scenarios cannot drift into several
# descriptions of several different code paths.
BRIDGE_PROBE = """import QtQuick
import Quickshell
import qs.components
import qs.services
import qs.modules.notch
import qs.modules.shelves

ShellRoot {
    id: root

    property var result: ({})
    property bool done: false
    property bool enable: Quickshell.env("PHONE_ENABLE") === "1"
    property bool expectSpawn: Quickshell.env("PHONE_SPAWN") === "1"
    property bool sentinel: Quickshell.env("PHONE_SENTINEL") === "1"
    property bool refreshWhileOff: Quickshell.env("PHONE_REFRESH_WHILE_OFF") === "1"
    property int phase: 0
    property int waits: 0
    property int settle: 0

    // The notch needs a real ScreenState and a real window to be built in,
    // the way tests/test_shelves.py builds the notch body.
    ScreenState { id: notchScreen; modelData: Quickshell.screens[0] }
    FloatingWindow { id: host; visible: true; implicitWidth: 400; implicitHeight: 400 }
    Component { id: notchComp; Notch {} }

    // Both hosts read Phone.available, and these are their two lists.
    function hostFacts(): var {
        const notch = notchComp.createObject(host.contentItem, {screenState: notchScreen});
        const ids = notch ? notch.tiles.map(t => t.id) : null;
        if (notch)
            notch.destroy();
        return ids;
    }

    // The tile bodies themselves, built the way their hosts build them, so
    // a tile that does not compile or does not lay out is a failing
    // assertion instead of an empty surface on somebody's desktop.
    function mount(url: string): var {
        const component = Qt.createComponent(url);
        if (component.status !== Component.Ready) {
            root.result.mountError = url + ": " + component.errorString();
            return null;
        }
        return component.createObject(host.contentItem, {width: 300});
    }

    function texts(item, out): var {
        if (!item)
            return out;
        if (typeof item.text === "string" && item.text.length > 0)
            out.push(item.text);
        const kids = item.children ?? [];
        for (let i = 0; i < kids.length; i++)
            root.texts(kids[i], out);
        return out;
    }

    function report(): void {
        root.result.spawns = Phone.spawns;
        root.result.devices = Phone.devices;
        root.result.reachable = Phone.reachable;
        root.result.available = Phone.available;
        root.result.toolPresent = Phone.toolPresent;
        root.result.lastError = Phone.lastError;
        root.result.shelfIds = ShelfTabs.forEdge("left").map(t => t.id);
        root.result.notchIds = root.hostFacts();
        const shelfTab = root.mount("modules/shelves/ShelfPhoneTab.qml");
        root.result.shelfTabTexts = root.texts(shelfTab, []);
        if (shelfTab)
            shelfTab.destroy();
        const notchTile = root.mount("modules/notch/NotchPhoneTile.qml");
        root.result.notchTileTexts = root.texts(notchTile, []);
        if (notchTile)
            notchTile.destroy();
        if (root.done)
            return;
        root.done = true;
        console.log("PHONE_FLAGS " + JSON.stringify(root.result));
        Qt.quit();
    }

    Timer {
        interval: 50
        repeat: true
        running: !root.done
        onTriggered: {
            if (root.phase === 0) {
                root.phase = 1;
                if (root.sentinel) {
                    // Parked on true so a test can tell an exit that
                    // reported 127 from an exit that never reported: only
                    // the first clears it.
                    Phone.toolPresent = true;
                    root.result.sentinel = true;
                }
                if (root.refreshWhileOff) {
                    // The tiles' way in, with the flag off: it must not
                    // start anything either.
                    Phone.refresh();
                }
                if (root.enable)
                    Settings.phoneBridge = true;
                return;
            }
            if (Phone.spawns === 0) {
                // No scan yet. With the flag off that is the whole
                // assertion, and five ticks is long enough for a stray one
                // to have appeared; with a scan expected, wait for it.
                if (++root.waits >= (root.expectSpawn ? 20 : 5))
                    root.report();
                return;
            }
            // A scan started. Its stdout and its exit land a tick or two
            // apart, so read the answer after both.
            if (++root.settle < 3)
                return;
            root.report();
        }
    }
}
"""

# The refresh path: the one way to ask the bridge again, called directly and
# from the Refresh row of each tile. The stub's call log is read from inside
# the probe, so a refresh that was accepted has to have really run the
# command before the probe moves to the next step.
REFRESH_PROBE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.services
import qs.modules.notch
import qs.modules.shelves

ShellRoot {
    id: root

    property var result: ({})
    property bool done: false
    property int tick: 0
    property int phase: 0
    property var tile: null

    FloatingWindow { id: host; visible: true; implicitWidth: 400; implicitHeight: 400 }

    FileView {
        id: callLog
        path: Quickshell.env("PHONE_CALLS")
        printErrors: false
    }

    function calls(): int {
        callLog.reload();
        const lines = String(callLog.text() ?? "").split("\\n");
        let n = 0;
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].trim().length > 0)
                n++;
        }
        return n;
    }

    // Every scan that started has reached the stub's log, which is the
    // independent observer: Phone.spawns counts the launch, the log counts
    // the command having run.
    function allRan(): bool {
        return Phone.spawns > 0 && root.calls() >= Phone.spawns;
    }

    // The clickable row carrying a label. The label's own subtree is
    // searched first and then its ancestors', so a clickable row added
    // later cannot stand in for the Refresh row.
    function clickable(item, label): var {
        function hasText(node): bool {
            if (typeof node.text === "string" && node.text === label)
                return true;
            const kids = node.children ?? [];
            for (let i = 0; i < kids.length; i++) {
                if (hasText(kids[i]))
                    return true;
            }
            return false;
        }
        function areaIn(node): var {
            if (typeof node.clicked === "function")
                return node;
            const kids = node.children ?? [];
            for (let i = 0; i < kids.length; i++) {
                const hit = areaIn(kids[i]);
                if (hit)
                    return hit;
            }
            return null;
        }
        for (let node = item; node; node = node.parent) {
            if (hasText(node)) {
                const hit = areaIn(node);
                if (hit)
                    return hit;
            }
        }
        return null;
    }

    function mount(url): var {
        const component = Qt.createComponent(url);
        if (component.status !== Component.Ready) {
            root.result.mountError = url + ": " + component.errorString();
            return null;
        }
        return component.createObject(host.contentItem, {width: 300});
    }

    function report(): void {
        if (root.done)
            return;
        root.done = true;
        root.result.spawns = Phone.spawns;
        console.log("PHONE_REFRESH " + JSON.stringify(root.result));
        Qt.quit();
    }

    Timer {
        interval: 50
        repeat: true
        running: !root.done
        onTriggered: {
            root.tick++;
            if (root.tick > 120) {
                // A step that never got its answer still reports, so a
                // failure names the step instead of timing out.
                root.report();
                return;
            }
            if (root.phase === 0) {
                root.phase = 1;
                Settings.phoneBridge = true;
                return;
            }
            if (root.phase === 1) {
                if (!root.allRan())
                    return;
                root.result.spawnsForFlag = Phone.spawns;
                root.result.callsForFlag = root.calls();
                root.phase = 2;
                return;
            }
            if (root.phase === 2) {
                // Three refreshes in one event loop turn, while the flag's
                // own scan is still running.
                Phone.refresh();
                Phone.refresh();
                Phone.refresh();
                root.result.spawnsForBurst = Phone.spawns;
                root.phase = 3;
                return;
            }
            if (root.phase === 3) {
                if (!root.allRan())
                    return;
                root.result.callsForBurst = root.calls();
                root.tile = root.mount("modules/shelves/ShelfPhoneTab.qml");
                root.phase = 4;
                return;
            }
            if (root.phase === 4) {
                const hit = root.clickable(root.tile, "Refresh");
                root.result.shelfClickable = hit !== null;
                if (hit)
                    hit.clicked(null);
                root.result.spawnsForShelfClick = Phone.spawns;
                root.phase = 5;
                return;
            }
            if (root.phase === 5) {
                if (!root.allRan())
                    return;
                root.result.callsForShelfClick = root.calls();
                if (root.tile)
                    root.tile.destroy();
                root.tile = root.mount("modules/notch/NotchPhoneTile.qml");
                root.phase = 6;
                return;
            }
            if (root.phase === 6) {
                const hit = root.clickable(root.tile, "Refresh");
                root.result.notchClickable = hit !== null;
                if (hit)
                    hit.clicked(null);
                root.result.spawnsForNotchClick = Phone.spawns;
                root.phase = 7;
                return;
            }
            if (root.phase === 7) {
                if (!root.allRan())
                    return;
                root.result.callsForNotchClick = root.calls();
                root.report();
            }
        }
    }
}
"""

# A stand-in for kdeconnect-cli: prints the fixture, records every call, and
# exits with PHONE_EXIT so a failing scan can be driven too.
STUB = '''#!/usr/bin/env python3
import json, os, sys
calls = os.environ.get("PHONE_CALLS")
if calls:
    with open(calls, "a") as f:
        f.write(json.dumps(sys.argv[1:]) + "\\n")
sys.stdout.write(os.environ.get("PHONE_OUT", ""))
sys.exit(int(os.environ.get("PHONE_EXIT", "0")))
'''


def flags(tmp_path: Path) -> dict:
    return run_probe(tmp_path, FLAGS_PROBE, marker="PHONE_FLAGS",
                     prefix="_phone_flags_")


def save(tmp_path: Path, flag: str, extra_env: dict) -> dict:
    return run_probe(tmp_path, SAVE_PROBE, extra_env={"PHONE_FLAG": flag, **extra_env},
                     marker="PHONE_SAVE", prefix="_phone_flags_")


def bridge(tmp_path: Path, extra_env: dict) -> dict:
    return run_probe(tmp_path, BRIDGE_PROBE, extra_env=extra_env,
                     marker="PHONE_FLAGS", prefix="_phone_flags_")


def refresh(tmp_path: Path, extra_env: dict) -> dict:
    return run_probe(tmp_path, REFRESH_PROBE, extra_env=extra_env,
                     marker="PHONE_REFRESH", prefix="_phone_flags_")


def stub_bin(tmp_path: Path, output: str, log: Path, exit_code: int = 0) -> dict:
    """PATH first entry holding a kdeconnect-cli that logs its argv."""
    bin_dir = tmp_path / "stub-bin"
    bin_dir.mkdir(exist_ok=True)
    stub = bin_dir / "kdeconnect-cli"
    stub.write_text(STUB)
    stub.chmod(0o755)
    return {
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "PHONE_CALLS": str(log),
        "PHONE_OUT": output,
        "PHONE_EXIT": str(exit_code),
    }


def calls(log: Path) -> list:
    return [json.loads(line) for line in log.read_text().splitlines()]


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_phone_flags_default_off_and_are_writable(tmp_path):
    out = flags(tmp_path)

    assert out["settings"] == [False] * 8, out
    assert out["config"] == [False] * 8, out
    assert out["wired"] is True, out
    assert out["restored"] is True, out


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
@pytest.mark.parametrize("flag", PHONE_FLAGS)
def test_phone_flag_reaches_settings_json(tmp_path, flag):
    # settings.json is the only surface these eight have today, so a flag
    # whose handler never fires is a switch that looks set and is not.
    log = tmp_path / "calls.jsonl"
    out = save(tmp_path, flag, stub_bin(tmp_path, "", log))

    assert out["flag"] == flag, out
    assert out["loaded"] is True, out
    assert out["assigned"] is True, out
    assert out["before"] is False, out
    assert out["value"] is True, out
    state = tmp_path / "home/.local/state/aphotic/settings.json"
    assert state.exists(), f"assigning {flag} wrote no settings.json"
    saved = json.loads(state.read_text())
    assert saved.get(flag) is True, saved


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_phone_bridge_spawns_nothing_while_the_flag_is_off(tmp_path):
    log = tmp_path / "calls.jsonl"
    out = bridge(tmp_path, {
        **stub_bin(tmp_path, f"{TEST_PHONE} Test Phone\n", log),
        "PHONE_REFRESH_WHILE_OFF": "1",
    })

    assert out["spawns"] == 0, out
    assert out["available"] is False, out
    assert out["devices"] == [], out
    assert "phone" not in out["shelfIds"], out
    assert out["notchIds"] is not None and "phone" not in out["notchIds"], out
    assert not log.exists(), "the bridge ran a command with its flag off"


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_phone_bridge_scans_once_and_parses_the_device_lines(tmp_path):
    log = tmp_path / "calls.jsonl"
    out = bridge(tmp_path, {
        **stub_bin(tmp_path, f"{TEST_PHONE} Test Phone\n{SECOND_PHONE} Second Phone\n", log),
        "PHONE_ENABLE": "1",
        "PHONE_SPAWN": "1",
    })

    assert out["spawns"] == 1, out
    assert out["toolPresent"] is True, out
    assert out["lastError"] == "", out
    assert out["reachable"] is True, out
    assert out["available"] is True, out
    assert out["devices"] == [
        {"id": TEST_PHONE, "label": "Test Phone"},
        {"id": SECOND_PHONE, "label": "Second Phone"},
    ], out
    assert calls(log) == [["--list-available", "--id-name-only"]], log.read_text()
    assert "phone" in out["shelfIds"], out
    assert out["notchIds"] is not None and "phone" in out["notchIds"], out
    # Both tiles list the devices and the one way to ask again.
    for key in ("shelfTabTexts", "notchTileTexts"):
        assert "Test Phone" in out[key], out
        assert "Second Phone" in out[key], out
        assert "Refresh" in out[key], out


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_phone_bridge_reports_no_device_without_failing(tmp_path):
    log = tmp_path / "calls.jsonl"
    out = bridge(tmp_path, {
        **stub_bin(tmp_path, "0 devices found\n", log),
        "PHONE_ENABLE": "1",
        "PHONE_SPAWN": "1",
    })

    assert out["spawns"] == 1, out
    assert out["toolPresent"] is True, out
    assert out["devices"] == [], out
    assert out["reachable"] is False, out
    assert out["available"] is False, out
    assert "phone" not in out["shelfIds"], out
    assert out["notchIds"] is not None and "phone" not in out["notchIds"], out
    assert calls(log) == [["--list-available", "--id-name-only"]], log.read_text()


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_phone_bridge_enabled_from_settings_json_scans_once(tmp_path):
    state = tmp_path / "home/.local/state/aphotic"
    state.mkdir(parents=True, exist_ok=True)
    (state / "settings.json").write_text(json.dumps({"phoneBridge": True}))
    log = tmp_path / "calls.jsonl"
    out = bridge(tmp_path, {
        **stub_bin(tmp_path, f"{TEST_PHONE} Test Phone\n", log),
        "PHONE_SPAWN": "1",
    })

    assert out["spawns"] == 1, out
    assert out["devices"] == [{"id": TEST_PHONE, "label": "Test Phone"}], out
    assert calls(log) == [["--list-available", "--id-name-only"]], log.read_text()


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_phone_bridge_without_the_command_is_not_an_error(tmp_path):
    # A PATH holding only what the probe itself is launched with, so the
    # host's own kdeconnect-cli cannot leak in and this reads the same on a
    # machine that has KDE Connect and on the CI runner that does not.
    #
    # Nothing here can assert that the missing tool left no trace: the
    # bridge's Process sets no stderr collector, Quickshell drops the
    # child's stderr, and with the tool absent the guarded command and the
    # bare one both exit 127. Deleting the guard fails
    # tests/test_profiles_shell_deps.py instead, which reads the command.
    bin_dir = tmp_path / "bare-bin"
    bin_dir.mkdir()
    for name in ("sh", "timeout", "qs"):
        (bin_dir / name).symlink_to(shutil.which(name))
    assert shutil.which("kdeconnect-cli", path=str(bin_dir)) is None, (
        "the bare PATH now answers for kdeconnect-cli, so this is no longer "
        "the tool-absent path")
    out = bridge(tmp_path, {
        "PATH": str(bin_dir),
        "PHONE_ENABLE": "1",
        "PHONE_SPAWN": "1",
        # toolPresent starts true, so reading it false below means a scan
        # exited 127 rather than that no exit was ever reported.
        "PHONE_SENTINEL": "1",
    })

    assert out["sentinel"] is True, out
    assert out["spawns"] == 1, out
    assert out["toolPresent"] is False, out
    assert out["devices"] == [], out
    assert out["available"] is False, out
    assert "phone" not in out["shelfIds"], out
    assert out["notchIds"] is not None and "phone" not in out["notchIds"], out


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_phone_bridge_reports_a_scan_that_failed(tmp_path):
    # The other half of the branch above: a tool that is there and fails
    # has to be told apart from a tool that is not there, and lastError has
    # to carry the code. Nothing else here covers a failure that is not
    # 127.
    log = tmp_path / "calls.jsonl"
    out = bridge(tmp_path, {
        **stub_bin(tmp_path, "", log, exit_code=42),
        "PHONE_ENABLE": "1",
        "PHONE_SPAWN": "1",
        "PHONE_SENTINEL": "1",
    })

    assert out["spawns"] == 1, out
    assert out["toolPresent"] is True, out
    assert out["lastError"] == "42", out
    assert out["devices"] == [], out
    assert out["available"] is False, out
    assert calls(log) == [["--list-available", "--id-name-only"]], log.read_text()


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_phone_bridge_refreshes_once_per_ask(tmp_path):
    # A burst of three refreshes in one turn is one scan: the flag's own
    # scan is still running, and nothing queues behind it. Then each tile's
    # Refresh row starts the next one.
    log = tmp_path / "calls.jsonl"
    out = refresh(tmp_path, {
        **stub_bin(tmp_path, f"{TEST_PHONE} Test Phone\n", log),
        "PHONE_ENABLE": "1",
    })

    assert out.get("mountError") is None, out
    assert out["spawnsForFlag"] == 1, out
    assert out["callsForFlag"] == 1, out
    assert out["spawnsForBurst"] == 2, out
    assert out["callsForBurst"] == 2, out
    assert out["shelfClickable"] is True, out
    assert out["spawnsForShelfClick"] == 3, out
    assert out["callsForShelfClick"] == 3, out
    assert out["notchClickable"] is True, out
    assert out["spawnsForNotchClick"] == 4, out
    assert out["callsForNotchClick"] == 4, out
    assert calls(log) == [["--list-available", "--id-name-only"]] * 4, log.read_text()
