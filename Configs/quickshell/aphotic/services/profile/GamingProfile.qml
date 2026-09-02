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
// no generic DBus client (only DBusMenu's tray types), so this shells out
// the same way the rest of the shell talks to system services. It is an
// event stream, not a poll: no timer, nothing runs between games.
//
// The subscription is a bare match rule rather than `gdbus monitor
// --dest com.feralinteractive.GameMode`, because addressing the name is
// what makes the bus *auto-activate* it: that spawned gamemoded at shell
// start, before any game existed, and gamemoded has no idle-exit, so it
// then stayed resident for the whole session. A match rule observes the
// same signals without ever addressing the name, so gamemoded runs only
// when something actually starts it -- gamemoderun, or the user's own
// gamemoded.service. Both halves verified live; see the PR.
//
// Nothing here ever stops gamemoded. If this shell never starts it there
// is nothing to tear down, and killing a daemon the user may have
// enabled deliberately would be exactly the sort of destructive
// automatic action the project rules prohibit.
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

    // dbus-monitor prints a signal across several lines -- the member on
    // one, its arguments on the following ones -- unlike gdbus, which put
    // the whole thing on a single line. So the member is latched here and
    // applied to the first int32 that follows it.
    property string _pendingMember: ""

    function _onLine(line: string): void {
        const member = line.match(/member=(GameRegistered|GameUnregistered)/);
        if (member) {
            root._pendingMember = member[1];
            return;
        }
        if (!root._pendingMember)
            return;

        const pid = line.match(/^\s*int32\s+(\d+)/);
        if (!pid)
            return;

        const member_ = root._pendingMember;
        root._pendingMember = "";
        if (member_ === "GameRegistered")
            root._add(parseInt(pid[1], 10));
        else
            root._remove(parseInt(pid[1], 10));
    }

    property Process _monitorProc: Process {
        running: root.enabled
        command: ["dbus-monitor", "--session", "type='signal',interface='com.feralinteractive.GameMode'"]
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
    //
    // Guarded on gamemoded already running, because addressing the name
    // is what auto-activates it, which is the whole thing this branch
    // stops doing. If the daemon is not up there is no game to catch, so
    // the guard costs nothing in the case that matters.
    property Process _listProc: Process {
        command: ["sh", "-c", "pgrep -x gamemoded >/dev/null 2>&1 && gdbus call --session --dest com.feralinteractive.GameMode --object-path /com/feralinteractive/GameMode --method com.feralinteractive.GameMode.ListGames"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const entry of text.match(/\(\d+, objectpath/g) ?? [])
                    root._add(parseInt(entry.slice(1), 10));
            }
        }
    }
}
