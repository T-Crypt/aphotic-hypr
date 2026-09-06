// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The diagnosis itself lives in bash (`aphotic recovery`,
// commands/cmd_recovery.sh) because it has to work with no shell running
// at all -- the terminal menu is the same four choices off the same
// evidence. This reads it and does nothing else clever.
Singleton {
    id: root

    property bool loaded: false
    property int failures: 0
    property string unit: ""
    property string suspectPlugin: ""
    property string lastChange: ""
    property string latestBackup: ""
    property string logTail: ""
    property string version: ""
    property bool safeMode: false

    // Set while an action is running, so the surface can say what it is
    // doing instead of sitting there looking unresponsive for the second
    // or two before it closes.
    property string applying: ""

    function refresh(): void {
        statusProc.running = true;
    }

    // Hand off and get out of the way. The action restarts the shell
    // itself, so this surface has no reason to still be on screen -- and
    // every reason not to be, since it holds exclusive keyboard focus.
    function apply(action: string): void {
        if (root.applying)
            return;
        root.applying = action;
        Quickshell.execDetached(["aphotic", "recovery", "apply", action]);
        quitTimer.start();
    }

    Component.onCompleted: root.refresh()

    Timer {
        id: quitTimer
        interval: 400
        onTriggered: Qt.quit()
    }

    Process {
        id: statusProc
        command: ["aphotic", "recovery", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.failures = data.failures ?? 0;
                    root.unit = data.unit ?? "";
                    root.suspectPlugin = data.suspectPlugin ?? "";
                    root.lastChange = data.lastChange ?? "";
                    root.latestBackup = data.latestBackup ?? "";
                    root.logTail = data.logTail ?? "";
                    root.version = data.version ?? "";
                    root.safeMode = data.safeMode === true;
                } catch (e) {
                    root.logTail = text;
                }
                root.loaded = true;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (!root.loaded && text.trim().length > 0) {
                    root.logTail = text.trim();
                    root.loaded = true;
                }
            }
        }
    }
}
