pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services
import qs.services.profile

// The Gaming profile: desktop-shell coordination around a running game,
// nothing more. gamemode already owns CPU governor and GPU clock state
// through its own cpugovctl/gpuclockctl the moment a game registers, so
// this deliberately does no performance tuning -- it engages DND, claims
// the game's VRAM at foreground priority, and runs the ProfileEngine
// lifecycle.
//
// DETECT is gamemoded's own session-bus signals. Quickshell 0.3.1 exposes
// no generic DBus client (only DBusMenu's tray types), so this shells
// gdbus the same way the rest of the shell talks to system services.
// `gdbus monitor` is an event stream, not a poll: no timer, nothing runs
// between games.
//
// Subscribing does activate gamemoded if it isn't already up. That is
// accepted rather than worked around: the alternative is polling for the
// daemon's existence, which is strictly worse than one idle daemon on a
// machine where the gaming layer was explicitly enabled.
QtObject {
    id: root

    property var gpuVram: null

    readonly property string profileId: "gaming"
    readonly property bool enabled: InstallProfile.gamingEnabled
    readonly property var activePids: Object.keys(root._games)
    readonly property bool active: root.activePids.length > 0

    property var _games: ({})
    property bool _registered: false

    Component.onCompleted: root._register()

    onEnabledChanged: {
        root._register();
        if (!root.enabled)
            root._reset();
    }

    // No gracefulStop: the claim is registered foreground, and
    // ResourceEngine._incumbent() sorts background claims ahead of
    // foreground ones when choosing who to offer suspending, so Gaming is
    // the side that raises a negotiation rather than the side answering
    // it. gamemode exposes no pause primitive either, so a hook here
    // would be a fake one. canSuspend("gaming") correctly stays false.
    //
    // Snapshot is the "notifications" part only, which StateSnapshot
    // defines as exactly {dnd: Settings.dndEnabled} -- the one thing this
    // profile changes. Naming it explicitly matters: an empty array is
    // NOT "capture nothing", StateSnapshot.capture() falls back to
    // allParts when the list is empty, which would snapshot and restore
    // theme/workspace/monitors this profile never touches.
    function _register(): void {
        if (root._registered || !root.enabled)
            return;
        root._registered = true;
        ProfileEngine.register({
            id: root.profileId,
            label: qsTr("Gaming"),
            snapshot: ["notifications"],
            onApply: () => DoNotDisturb.setGamingActive(true),
            onRestore: () => DoNotDisturb.setGamingActive(false)
        });
        root._listProc.running = true;
    }

    function _reset(): void {
        for (const pid of Object.keys(root._games))
            root._remove(parseInt(pid, 10));
    }

    function _add(pid: int): void {
        const key = String(pid);
        if (!pid || Object.prototype.hasOwnProperty.call(root._games, key))
            return;

        const next = Object.assign({}, root._games);
        next[key] = true;
        root._games = next;

        if (root.gpuVram)
            root.gpuVram.adopt(pid, root.profileId, "foreground");

        if (!ProfileEngine.isActive(root.profileId))
            ProfileEngine.activate(root.profileId, "gamemode");
    }

    function _remove(pid: int): void {
        const key = String(pid);
        if (!Object.prototype.hasOwnProperty.call(root._games, key))
            return;

        const next = Object.assign({}, root._games);
        delete next[key];
        root._games = next;

        if (root.gpuVram)
            root.gpuVram.unadopt(pid);

        if (Object.keys(root._games).length === 0 && ProfileEngine.isActive(root.profileId))
            ProfileEngine.deactivate(root.profileId, "gamemode");
    }

    function _onLine(line: string): void {
        const registered = line.match(/GameRegistered \((\d+),/);
        if (registered) {
            root._add(parseInt(registered[1], 10));
            return;
        }
        const unregistered = line.match(/GameUnregistered \((\d+),/);
        if (unregistered)
            root._remove(parseInt(unregistered[1], 10));
    }

    property Process _monitorProc: Process {
        running: root.enabled
        command: ["gdbus", "monitor", "--session", "--dest", "com.feralinteractive.GameMode"]
        stdout: SplitParser {
            onRead: line => root._onLine(line)
        }
        onExited: {
            if (root.enabled)
                root._restartTimer.restart();
        }
    }

    // gdbus monitor dying (gamemoded restarted, bus hiccup) would
    // otherwise silently end detection for the rest of the session.
    property Timer _restartTimer: Timer {
        interval: 5000
        onTriggered: {
            if (root.enabled && !root._monitorProc.running)
                root._monitorProc.running = true;
        }
    }

    // Catches a game already registered when the shell starts or reloads
    // mid-session -- the signal stream only carries transitions.
    property Process _listProc: Process {
        command: ["gdbus", "call", "--session", "--dest", "com.feralinteractive.GameMode", "--object-path", "/com/feralinteractive/GameMode", "--method", "com.feralinteractive.GameMode.ListGames"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const entry of text.match(/\(\d+, objectpath/g) ?? [])
                    root._add(parseInt(entry.slice(1), 10));
            }
        }
    }
}
