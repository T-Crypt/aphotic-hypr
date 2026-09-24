pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config

Singleton {
    id: root

    readonly property var toplevels: Hyprland.toplevels
    readonly property var workspaces: Hyprland.workspaces
    readonly property var monitors: Hyprland.monitors
    readonly property bool usingLua: Hyprland.usingLua

    readonly property HyprlandToplevel activeToplevel: {
        const t = Hyprland.activeToplevel;
        return t?.workspace?.name.startsWith("special:") || Hyprland.focusedWorkspace?.toplevels.values.length > 0 ? t : null;
    }
    readonly property HyprlandWorkspace focusedWorkspace: Hyprland.focusedWorkspace
    readonly property HyprlandMonitor focusedMonitor: Hyprland.focusedMonitor
    readonly property int activeWsId: focusedWorkspace?.id ?? 1

    property string lastSpecialWorkspace: ""

    // hyprctl's own IPC (Quickshell.Hyprland) has no keyboard-device API at
    // all -- these three were referenced by StatusIcons.qml already (kbLayout
    // display, lockStatus collapse check) but never defined here, a
    // pre-existing dead reference. Backed by `hyprctl devices -j` since
    // that's the only source for capsLock/numLock/active layout.
    property string kbLayout: ""
    property bool capsLock: false
    property bool numLock: false

    signal configReloaded
    // Re-emitted so anything that needs the compositor's raw stream
    // (services/profile/ProfileEvents.qml) hangs off this one handler
    // instead of opening a second Connections on Hyprland itself. Emitted
    // after the v2 filter below, so subscribers see the same
    // once-per-event stream this file acts on rather than duplicates.
    signal rawEvent(name: string, data: string)

    function dispatch(request: string): void {
        Hyprland.dispatch(request);
    }

    function cycleSpecialWorkspace(direction: string): void {
        const openSpecials = workspaces.values.filter(w => w.name.startsWith("special:") && w.lastIpcObject.windows > 0);

        if (openSpecials.length === 0)
            return;

        const activeSpecial = focusedMonitor.lastIpcObject.specialWorkspace.name ?? "";

        if (!activeSpecial) {
            if (lastSpecialWorkspace) {
                const workspace = workspaces.values.find(w => w.name === lastSpecialWorkspace);
                if (workspace && workspace.lastIpcObject.windows > 0) {
                    dispatch(usingLua ? `hl.dsp.focus({ workspace = "${lastSpecialWorkspace}" })` : `workspace ${lastSpecialWorkspace}`);
                    return;
                }
            }
            dispatch(usingLua ? `hl.dsp.focus({ workspace = "${openSpecials[0].name}" })` : `workspace ${openSpecials[0].name}`);
            return;
        }

        const currentIndex = openSpecials.findIndex(w => w.name === activeSpecial);
        let nextIndex = 0;

        if (currentIndex !== -1) {
            if (direction === "next")
                nextIndex = (currentIndex + 1) % openSpecials.length;
            else
                nextIndex = (currentIndex - 1 + openSpecials.length) % openSpecials.length;
        }

        dispatch(usingLua ? `hl.dsp.focus({ workspace = "${openSpecials[nextIndex].name}" })` : `workspace ${openSpecials[nextIndex].name}`);
    }

    function monitorNames(): list<string> {
        return monitors.values.map(e => e.name);
    }

    function monitorFor(screen: ShellScreen): HyprlandMonitor {
        return Hyprland.monitorFor(screen);
    }

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            if (n.endsWith("v2"))
                return;

            root.rawEvent(n, event.data ?? "");

            if (n === "configreloaded") {
                root.configReloaded();
            } else if (["workspace", "moveworkspace", "activespecial", "focusedmon"].includes(n)) {
                Hyprland.refreshWorkspaces();
                Hyprland.refreshMonitors();
            } else if (["openwindow", "closewindow", "movewindow"].includes(n)) {
                Hyprland.refreshToplevels();
                Hyprland.refreshWorkspaces();
            } else if (n === "activelayout") {
                root.refreshKeyboardState();
            } else if (n.includes("mon")) {
                Hyprland.refreshMonitors();
            } else if (n.includes("workspace")) {
                Hyprland.refreshWorkspaces();
            } else if (n.includes("window") || n.includes("group") || ["pin", "fullscreen", "changefloatingmode", "minimize"].includes(n)) {
                Hyprland.refreshToplevels();
                // A workspace's hasfullscreen flag only moves on this
                // event, and RenderGate reads it to decide whether
                // anything decorative can still be seen.
                if (n === "fullscreen")
                    Hyprland.refreshWorkspaces();
            }
        }

        target: Hyprland
    }

    function refreshKeyboardState(): void {
        keyboardStateProc.running = true;
    }

    Process {
        id: keyboardStateProc
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const devices = JSON.parse(text);
                    const kb = devices.keyboards?.find(k => k.main) ?? devices.keyboards?.[0];
                    if (kb) {
                        root.kbLayout = kb.active_keymap ?? "";
                        root.capsLock = !!kb.capsLock;
                        root.numLock = !!kb.numLock;
                    }
                } catch (e) {
                    // Malformed/empty output from a transient hyprctl failure -- keep last known state.
                }
            }
        }
    }

    // Caps and num lock come from the kernel's keyboard LEDs, read in
    // process instead of forking hyprctl every tick. Hyprland sets every
    // keyboard's LEDs to the shared lock state, so any LED that reads on
    // means the lock is on. With no keyboard LEDs (VMs, virtual keyboards)
    // this falls back to polling hyprctl.
    property list<string> _ledPaths: []

    function _readLeds(): void {
        let caps = false;
        let num = false;
        for (let i = 0; i < ledViews.count; i++) {
            const view = ledViews.objectAt(i);
            view.reload();
            const text = view.text().trim();
            if (text === "") {
                // The device went away; list the LEDs again.
                ledListProc.running = true;
                return;
            }
            if (text !== "0") {
                if (view.path.includes("::capslock/"))
                    caps = true;
                else
                    num = true;
            }
        }
        root.capsLock = caps;
        root.numLock = num;
    }

    Process {
        id: ledListProc
        command: ["sh", "-c", "for f in /sys/class/leds/*::capslock/brightness /sys/class/leds/*::numlock/brightness; do [ -r \"$f\" ] && echo \"$f\"; done"]
        stdout: StdioCollector {
            onStreamFinished: root._ledPaths = text.split("\n").filter(l => l.length > 0)
        }
    }

    Instantiator {
        id: ledViews
        model: root._ledPaths
        delegate: FileView {
            required property string modelData
            path: modelData
            blockLoading: true
            printErrors: false
        }
    }

    Component.onCompleted: {
        root.refreshKeyboardState();
        ledListProc.running = true;
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            if (root._ledPaths.length > 0)
                root._readLeds();
            else
                root.refreshKeyboardState();
        }
    }

    Connections {
        function onLastIpcObjectChanged(): void {
            const specialName = root.focusedMonitor.lastIpcObject.specialWorkspace.name;

            if (specialName && specialName.startsWith("special:")) {
                root.lastSpecialWorkspace = specialName;
            }
        }

        target: root.focusedMonitor
    }

    IpcHandler {
        function cycleSpecialWorkspace(direction: string): void {
            root.cycleSpecialWorkspace(direction);
        }

        function listSpecialWorkspaces(): string {
            return root.workspaces.values.filter(w => w.name.startsWith("special:") && w.lastIpcObject.windows > 0).map(w => w.name).join("\n");
        }

        target: "hypr"
    }
}
