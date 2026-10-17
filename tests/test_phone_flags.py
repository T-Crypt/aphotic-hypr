"""The phone stack's flags and its device bridge, offscreen.

Flags first: all nine default off on a fresh HOME, and the bridge flag
actually moves when something assigns it, so a later phase proving the
bridge reads a value rather than a constant. Then the save half: each of
the nine flags assigned on its own has to reach settings.json, because
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
    "phoneMessages",
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
                Settings.phoneIcons, Settings.phoneCamera, Settings.phoneMic, Settings.phoneLocalSend,
                Settings.phoneMessages
            ];
            root.result.config = [
                Config.phone.bridge, Config.phone.mirror, Config.phone.calls, Config.phone.alarms,
                Config.phone.icons, Config.phone.camera, Config.phone.mic, Config.phone.localSend,
                Config.phone.messages
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

# The message store: PHONE_MESSAGES turns its flag on from inside,
# PHONE_SEND sends one message through the stub, PHONE_INCOMING records
# one incoming message without touching the command. The stub's call log
# is the independent observer for the send argv.
MESSAGES_PROBE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root

    property var result: ({})
    property bool done: false
    property bool enable: Quickshell.env("PHONE_MESSAGES") === "1"
    property bool bridge: Quickshell.env("PHONE_BRIDGE") === "1"
    property bool send: Quickshell.env("PHONE_SEND") === "1"
    property bool incoming: Quickshell.env("PHONE_INCOMING") === "1"
    property bool retry: Quickshell.env("PHONE_RETRY") === "1"
    property string device: "aaaaaaaa_bbbb_cccc_dddd_eeeeffff0000"
    property string dest: "+15551234567"
    property int tick: 0
    property int phase: 0
    property bool retrySent: false
    property int sendsBeforeRetry: 0
    property int settle: 0

    FileView {
        id: callLog
        path: Quickshell.env("PHONE_CALLS")
        printErrors: false
    }

    function sendCalls(): int {
        callLog.reload();
        const lines = String(callLog.text() ?? "").split("\\n");
        let n = 0;
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("--send-sms") >= 0)
                n++;
        }
        return n;
    }

    function report(): void {
        if (root.done)
            return;
        root.done = true;
        root.result.spawns = PhoneMessages.spawns;
        root.result.toolPresent = PhoneMessages.toolPresent;
        root.result.lastError = PhoneMessages.lastError;
        root.result.enabled = PhoneMessages.enabled;
        root.result.available = PhoneMessages.available;
        root.result.threads = PhoneMessages.threadsFor(root.device);
        root.result.failed = PhoneMessages.failed;
        root.result.sends = root.sendCalls();
        console.log("PHONE_MESSAGES " + JSON.stringify(root.result));
        Qt.quit();
    }

    Timer {
        interval: 50
        repeat: true
        running: !root.done
        onTriggered: {
            root.tick++;
            if (root.tick > 120) {
                root.report();
                return;
            }
            if (root.phase === 0) {
                root.phase = 1;
                if (root.bridge)
                    Settings.phoneBridge = true;
                if (root.enable)
                    Settings.phoneMessages = true;
                return;
            }
            if (root.phase === 1) {
                // The bridge scan settles first when it runs, so the
                // send below observes the reachable state above it.
                if (root.bridge && Phone.spawns === 0)
                    return;
                if (root.send)
                    PhoneMessages.sendSms(root.device, root.dest, "hello");
                if (root.incoming)
                    PhoneMessages.addIncoming(root.device, root.dest, "hi", 1700000000000);
                root.phase = 2;
                return;
            }
            if (root.phase === 2) {
                // A send that started has reached the stub's log, which is
                // the independent observer beyond the spawn count.
                if (root.send && PhoneMessages.spawns > 0 && root.sendCalls() < PhoneMessages.spawns)
                    return;
                if (root.retry) {
                    root.sendsBeforeRetry = root.sendCalls();
                    root.retrySent = PhoneMessages.failed.length > 0;
                    if (root.retrySent)
                        PhoneMessages.retry(PhoneMessages.failed[0]);
                    root.phase = 3;
                    return;
                }
                root.report();
                return;
            }
            // The retried send has to reach the log, then settle so its
            // exit code lands before the report reads the failed list.
            if (root.phase === 3) {
                if (root.retrySent && root.sendCalls() <= root.sendsBeforeRetry)
                    return;
                if (++root.settle < 2)
                    return;
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


def messages(tmp_path: Path, extra_env: dict) -> dict:
    return run_probe(tmp_path, MESSAGES_PROBE, extra_env=extra_env,
                     marker="PHONE_MESSAGES", prefix="_phone_messages_")


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

    assert out["settings"] == [False] * 9, out
    assert out["config"] == [False] * 9, out
    assert out["wired"] is True, out
    assert out["restored"] is True, out


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
@pytest.mark.parametrize("flag", PHONE_FLAGS)
def test_phone_flag_reaches_settings_json(tmp_path, flag):
    # settings.json is the only surface these nine have today, so a flag
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


MSG_DEVICE = TEST_PHONE
MSG_DEST = "+15551234567"
MSG_ARGV = ["--send-sms", "hello", "--destination", MSG_DEST, "-d", MSG_DEVICE]


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_phone_messages_sends_through_the_stub_and_records_the_thread(tmp_path):
    log = tmp_path / "calls.jsonl"
    out = messages(tmp_path, {
        **stub_bin(tmp_path, f"{TEST_PHONE} Test Phone\n", log),
        "PHONE_BRIDGE": "1",
        "PHONE_MESSAGES": "1",
        "PHONE_SEND": "1",
    })

    assert out["enabled"] is True, out
    assert out["available"] is True, out
    assert out["spawns"] == 1, out
    assert out["sends"] == 1, out
    assert out["toolPresent"] is True, out
    assert out["lastError"] == "", out
    assert MSG_ARGV in calls(log), log.read_text()
    assert len(out["threads"]) == 1, out
    entry = out["threads"][0]
    assert entry["address"] == MSG_DEST, out
    assert entry["body"] == "hello", out
    assert entry["direction"] == "out", out


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_phone_messages_records_an_incoming_message_without_the_command(tmp_path):
    log = tmp_path / "calls.jsonl"
    out = messages(tmp_path, {
        **stub_bin(tmp_path, f"{TEST_PHONE} Test Phone\n", log),
        "PHONE_BRIDGE": "1",
        "PHONE_MESSAGES": "1",
        "PHONE_INCOMING": "1",
    })

    assert out["spawns"] == 0, out
    assert len(out["threads"]) == 1, out
    entry = out["threads"][0]
    assert entry == {
        "deviceId": MSG_DEVICE, "address": MSG_DEST, "body": "hi",
        "timestamp": 1700000000000, "direction": "in",
    }, out


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_phone_messages_sends_nothing_while_its_flag_is_off(tmp_path):
    log = tmp_path / "calls.jsonl"
    out = messages(tmp_path, {
        **stub_bin(tmp_path, f"{TEST_PHONE} Test Phone\n", log),
        "PHONE_SEND": "1",
    })

    # The send never runs: the surface is gated behind the bridge, so
    # with both flags off there is no spawn, no stub call, and no entry.
    assert out["enabled"] is False, out
    assert out["available"] is False, out
    assert out["spawns"] == 0, out
    assert out["sends"] == 0, out
    assert out["threads"] == [], out


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_phone_messages_keeps_a_send_that_failed(tmp_path):
    # A send that exits non-zero never reached the phone, so it must not be
    # recorded as delivered and must not vanish: it belongs in the failed
    # list with the code that kept it from going out.
    log = tmp_path / "calls.jsonl"
    out = messages(tmp_path, {
        **stub_bin(tmp_path, f"{TEST_PHONE} Test Phone\n", log, exit_code=1),
        "PHONE_BRIDGE": "1",
        "PHONE_MESSAGES": "1",
        "PHONE_SEND": "1",
    })

    assert out["spawns"] == 1, out
    assert out["sends"] == 1, out
    assert out["toolPresent"] is True, out
    assert out["lastError"] == "1", out
    assert out["threads"] == [], out
    assert len(out["failed"]) == 1, out
    entry = out["failed"][0]
    assert entry["deviceId"] == MSG_DEVICE, out
    assert entry["destination"] == MSG_DEST, out
    assert entry["body"] == "hello", out
    assert entry["error"] == "1", out
    assert MSG_ARGV in calls(log), log.read_text()


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_phone_messages_without_the_command_keeps_the_message_without_an_error(tmp_path):
    # Exit 127 is the guard saying kdeconnect-cli is not installed, which
    # Phone.qml reports as no error at all. The send still did not happen,
    # so the message stays in the failed list, but lastError stays empty.
    bin_dir = tmp_path / "bare-bin"
    bin_dir.mkdir()
    for name in ("sh", "timeout", "qs"):
        (bin_dir / name).symlink_to(shutil.which(name))
    out = messages(tmp_path, {
        "PATH": str(bin_dir),
        "PHONE_BRIDGE": "1",
        "PHONE_MESSAGES": "1",
        "PHONE_SEND": "1",
    })

    assert out["spawns"] == 1, out
    assert out["toolPresent"] is False, out
    assert out["lastError"] == "", out
    assert out["threads"] == [], out
    assert len(out["failed"]) == 1, out
    assert out["failed"][0]["body"] == "hello", out
    assert out["failed"][0]["error"] == "127", out


@pytest.mark.skipif(shutil.which("qs") is None,
                    reason="needs Quickshell (qs) to run the shell probe")
def test_phone_messages_retry_resends_a_failed_message(tmp_path):
    # The failed entry is one a person can act on: retry() puts it back on
    # the queue and the stub sees the same argv a second time. Nothing runs
    # on its own, so the second send only happens because retry() asked.
    log = tmp_path / "calls.jsonl"
    out = messages(tmp_path, {
        **stub_bin(tmp_path, f"{TEST_PHONE} Test Phone\n", log, exit_code=1),
        "PHONE_BRIDGE": "1",
        "PHONE_MESSAGES": "1",
        "PHONE_SEND": "1",
        "PHONE_RETRY": "1",
    })

    assert out["spawns"] == 2, out
    assert out["sends"] == 2, out
    send_calls = [c for c in calls(log) if "--send-sms" in c]
    assert send_calls == [MSG_ARGV, MSG_ARGV], log.read_text()
    assert len(out["failed"]) == 1, out
    assert out["failed"][0]["body"] == "hello", out
