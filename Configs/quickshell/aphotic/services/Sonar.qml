pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "SonarPolicy.js" as Policy

// The Sonar session. One ping at a time, owned here: the shared progress
// value, the cancellation generation, the target snapshot taken once at
// the start, and the lifetime that ends the whole composition.
//
// The windows themselves live in modules/sonar/SonarHost.qml; they bind
// to this session and exist only while it does. At rest this singleton
// holds no timers, no processes and no geometry -- the sweep animation
// and the lifetime timer run only between ping and teardown.
//
// This singleton acts on its own (it binds the shortcut while enabled
// and answers IPC), so it needs a construction site in shell.qml's
// `_residentSingletons` or none of the below ever runs.
Singleton {
    id: root

    readonly property bool enabled: Settings.sonarEnabled

    // Session state. `origin` and `outputs` are logical desktop
    // coordinates -- the one shared plane every output clips its slice
    // of the same ring out of, gaps and negative positions included.
    property bool active: false
    property real progress: 0
    property var origin: null
    property var outputs: []
    property var targets: []
    property var screenStates: []
    readonly property var sessionScreen: root._sessionScreen
    property var lastTargets: []
    readonly property var visibleTargets: root.targets.filter(t => t.ghost ? SonarDiscovery.current(t) : EchoRegistry.isCurrent(t))
    property real maxRadius: 1
    property string focusOutput: ""
    property int generation: 0

    // Reduced motion: same outlines and labels, no sweep -- a static ring
    // at the origin and the two-second timeout. RenderGate.decorative is
    // false under a fullscreen window or a reduced-motion context too.
    readonly property bool reduced: !RenderGate.decorative

    // --- keybind, following WorkspaceKeybind.qml -----------------------
    // Free on a stock install (no grave binding ships and none was live
    // when checked). A user binding wins: the conflict check reads
    // `hyprctl binds -j` before the bind is ever asserted, and a bind is
    // never asserted while the check is unresolved.
    readonly property string combo: "SUPER + grave"
    readonly property string legacyCombo: "SUPER, grave"
    readonly property string description: "Ping Sonar discovery"
    readonly property string command: "qs -c aphotic ipc call sonar ping"

    property bool _checked: false
    property bool _conflict: false
    property bool _checking: false
    property bool _checkAgain: false
    property bool _checkExited: false
    property bool _checkCollected: false
    property int _checkCode: -1
    property string _applied: ""
    property var _sessionScreen: null

    readonly property bool bindWanted: root.enabled && root._checked && !root._conflict
    readonly property string desiredForm: !root.bindWanted ? "" : (Hypr.usingLua ? "lua" : "legacy")
    readonly property string conflictReason: !root.enabled ? ""
        : root._conflict ? "SUPER + grave is already bound"
        : !root._checked ? "Shortcut check unavailable; use Preview or IPC"
        : ""

    function ping(screenState: var): void {
        // Both the IPC route and the keybind route land here, so one
        // gate covers both.
        if (!Policy.canPing(root.enabled, Surfaces.blocking, SessionLockState.locked))
            return;
        const outs = root._outputGeometry();
        if (outs.length === 0)
            return;
        // A second explicit ping restarts the one session instead of
        // stacking overlays.
        root.dismiss();
        root.generation += 1;
        root.outputs = outs;
        root.focusOutput = root._focusedOutputName();
        root._sessionScreen = screenState;
        HyprKeybinds.refresh();
        const live = EchoRegistry.snapshot();
        root.targets = live.concat(SonarDiscovery.snapshot(outs, live));
        root.lastTargets = root.targets.map(t => ({id:t.id,output:t.output,label:t.label,shortcut:t.shortcut,reason:t.reason || ""}));
        cursorQuery.generation = root.generation;
        cursorQuery.running = false;
        cursorQuery.running = true;
    }

    function activateGhost(target: var): bool {
        if (!root.active || !target) return false;
        const owned = root.visibleTargets.find(t => t.id === target.id && t.output === target.output && t.ghost);
        if (!owned) return false;
        const state = SonarDiscovery.stateFor(owned.output);
        const eligible = SonarDiscovery.current(owned);
        // Capture the destination before teardown clears the session screen.
        // Activation rechecks registry eligibility after dismissal as well.
        root.dismiss();
        const result = eligible && SonarDiscovery.activate(owned, state);
        if (!result) Notifs.notify(qsTr("Feature unavailable"), qsTr("Review the feature in Settings."), [], "Aphotic");
        return result;
    }

    function dismiss(): void {
        root.generation += 1;
        cursorQuery.running = false;
        root.active = false;
        root.progress = 0;
        root.targets = [];
        root.origin = null;
        root.outputs = [];
        root.focusOutput = "";
        sweep.stop();
        lifetime.stop();
        if (root._sessionScreen) {
            root._sessionScreen.sonar = false;
            root._sessionScreen = null;
        }
    }

    function _start(origin: var): void {
        if (!Policy.canPing(root.enabled, Surfaces.blocking, SessionLockState.locked)) {
            root.dismiss();
            return;
        }
        root.origin = origin;
        root.maxRadius = Math.max(1, root._radiusFor(origin, root.outputs));
        root.active = true;
        root.progress = 0;
        // The flag, not a direct track(): ScreenState reports flag
        // changes into the surface stack, the same contract every other
        // surface's opener follows.
        if (root._sessionScreen)
            root._sessionScreen.sonar = true;
        if (!root.reduced)
            sweep.restart();
        else
            root.progress = 1;
        lifetime.restart();
    }

    // Farthest output corner from the origin, in the shared logical
    // plane. One circle for the whole desktop.
    function _radiusFor(point: var, outputs: var): real {
        var result = 1;
        outputs.forEach(function (o) {
            [o.x, o.x + o.width].forEach(function (x) {
                [o.y, o.y + o.height].forEach(function (y) {
                    result = Math.max(result, Math.hypot(x - point.x, y - point.y));
                });
            });
        });
        return result;
    }

    function _outputGeometry(): var {
        return Quickshell.screens.map(s => ({
            name: s.name, x: s.x, y: s.y, width: s.width, height: s.height
        }));
    }

    function _focusedOutputName(): string {
        return Hypr.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "";
    }

    function _fallbackOrigin(): var {
        const focused = root.outputs.find(o => o.name === root.focusOutput) ?? root.outputs[0];
        return Policy.originFallback(focused);
    }

    function refreshShortcut(): void {
        if (!root.enabled) return;
        if (root._checking) { root._checkAgain = true; return; }
        root._checking = true;
        root._checkAgain = false;
        root._checkExited = false;
        root._checkCollected = false;
        root._checkCode = -1;
        bindsCheck.running = true;
    }

    function _finishShortcutCheck(): void {
        if (!root._checkExited || !root._checkCollected) return;
        root._checking = false;
        if (root._checkAgain) {
            root._checkAgain = false;
            Qt.callLater(root.refreshShortcut);
            return;
        }
        if (root._checkCode !== 0) {
            root._checked = false;
            root._conflict = false;
            return;
        }
        try {
            const binds = JSON.parse(bindsOut.text);
            if (!Array.isArray(binds)) throw new Error("Invalid bind table");
            root._conflict = Policy.superBindConflict(binds);
        } catch (e) {
            root._checked = false;
            root._conflict = false;
            return;
        }
        root._checked = true;
    }

    Connections {
        target: Hypr
        function onConfigReloaded(): void {
            // A reload discards runtime binds; forget ownership before rechecking.
            root._applied = "";
            root._checked = false;
            root._conflict = false;
            root.refreshShortcut();
        }
    }

    onEnabledChanged: {
        root.dismiss();
        // Fresh conflict reading per enable; never assert the bind while
        // the reading is unresolved, so a user binding is never replaced.
        root._checked = false;
        root._conflict = false;
        root._sync();
        root.refreshShortcut();
    }

    // Cancellation precedence: lock, blocking prompt, disable. The
    // sonar flag in the surface stack also closes through the normal
    // transition when an ordinary surface opens; this watcher is the
    // same answer for everything that reports through `changed`.
    Connections {
        target: SessionLockState

        function onLockedChanged(): void {
            if (SessionLockState.locked)
                root.dismiss();
        }
    }

    Connections {
        target: Surfaces

        function onBlockingChanged(): void {
            if (Surfaces.blocking)
                root.dismiss();
        }

        function onChanged(screenState: var, name: string, open: bool): void {
            if (open && name !== "sonar" && root.active && (screenState === root._sessionScreen || Array.from(root.screenStates).includes(screenState)))
                root.dismiss();
        }
    }

    // An output attached or removed mid-ping invalidates the geometry
    // the session was started with.
    readonly property string _outputLayout: JSON.stringify(root._outputGeometry())
    on_OutputLayoutChanged: root.dismiss()

    // --- session timing -------------------------------------------------
    // One finite animation from ping to teardown; radius and fade are
    // pure functions of it (SonarPolicy.js). Nothing repeats.
    NumberAnimation {
        id: sweep

        target: root
        property: "progress"
        from: 0
        to: 1
        duration: Policy.LIFETIME_MS
        easing.type: Easing.Linear
    }

    Timer {
        id: lifetime

        interval: Policy.LIFETIME_MS
        onTriggered: root.dismiss()
    }

    Process {
        id: cursorQuery

        property int generation: 0

        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            id: cursorOut
        }

        onExited: (code, status) => {
            if (cursorQuery.generation !== root.generation)
                return;
            // A failed or unreadable cursor query is the fallback path,
            // not an abort: the focused output's center still gives a
            // real origin (SonarPolicy.parseCursorPos returns null).
            root._start(Policy.parseCursorPos(cursorOut.text) ?? root._fallbackOrigin());
        }
    }

    // --- keybind plumbing, same split as WorkspaceKeybind.qml -----------
    // `hyprctl keyword` is refused under the Lua parser; the runtime
    // equivalent is `hl.bind` through `hyprctl eval`.
    function _bindArgs(form: string): var {
        if (form === "lua")
            return ["hyprctl", "eval", `hl.bind("${root.combo}", hl.dsp.exec_cmd("${root.command}"), { description = "${root.description}" })`];
        return ["hyprctl", "keyword", "bindd", `${root.legacyCombo}, ${root.description}, exec, ${root.command}`];
    }

    function _unbindArgs(form: string): var {
        if (form === "lua")
            return ["hyprctl", "eval", `hl.unbind("${root.combo}")`];
        return ["hyprctl", "keyword", "unbind", root.legacyCombo];
    }

    function _sync(): void {
        const want = root.desiredForm;
        const had = root._applied;
        if (want === had)
            return;
        root._applied = want;
        binder.command = want.length > 0 ? root._bindArgs(want) : root._unbindArgs(had);
        binder.running = false;
        binder.running = true;
    }

    onDesiredFormChanged: root._sync()

    Component.onCompleted: {
        root._sync();
        root.refreshShortcut();
    }

    Component.onDestruction: {
        root.dismiss();
        if (root._applied.length > 0)
            Quickshell.execDetached(root._unbindArgs(root._applied));
    }

    Process {
        id: binder
    }

    Process {
        id: bindsCheck

        command: ["hyprctl", "-j", "binds"]
        stdout: StdioCollector {
            id: bindsOut
            onStreamFinished: {
                root._checkCollected = true;
                root._finishShortcutCheck();
            }
        }

        onExited: (code, status) => {
            root._checkCode = code;
            root._checkExited = true;
            root._finishShortcutCheck();
        }
    }
}
