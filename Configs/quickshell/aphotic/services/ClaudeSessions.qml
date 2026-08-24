pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Presence/count of running Claude Code CLI processes, polled once here
// and shared by the bar's ClaudeSessionStatus icon and its
// ClaudeSessionPopout -- same "one service, icon + popout both read it"
// shape as every other status entry (Audio, Bluetooth, PowerProfiles, ...).
Singleton {
    id: root

    property int count: 0

    // Finds the first Hyprland toplevel that looks like a terminal running
    // claude -- class match catches the common case (a kitty window running
    // the CLI), title match catches terminals that show the running command
    // in their title bar (e.g. foot, wezterm).
    function focusSession(): void {
        const toplevel = Hypr.toplevels.values.find(w => (w.lastIpcObject?.class ?? "").toLowerCase().includes("kitty") || (w.title ?? "").toLowerCase().includes("claude"));
        if (!toplevel)
            return;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ address = "${toplevel.address}" })` : `focuswindow address:${toplevel.address}`);
    }

    Process {
        id: pgrepProc

        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim(), 10);
                root.count = isNaN(n) ? 0 : n;
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        // -x anchors on the exact process name so this never counts its own
        // pgrep invocation or an unrelated binary that merely mentions
        // "claude" somewhere in its argv.
        onTriggered: pgrepProc.exec(["pgrep", "-x", "-c", "claude"])
    }
}
