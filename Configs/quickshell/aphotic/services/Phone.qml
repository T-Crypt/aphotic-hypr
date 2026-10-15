pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "PhonePolicy.js" as Policy

// The phone bridge: the one place the shell asks about a phone. Its flag
// turns the asking on, the tile's refresh row asks again, and in between it
// holds the last answer. No Timer -- kdeconnect-cli answers out of the
// daemon's own discovery, so a scan at rest would spend a process forever
// to learn nothing new. Later capabilities sit behind this service rather
// than inside it: they read `available` and add rows to the same tiles.
Singleton {
    id: root

    readonly property bool enabled: Settings.phoneBridge

    // The last scan's answer. `--list-available` reports reachable devices
    // only, so reachability is a fact about the list, not about a row.
    property var devices: []

    readonly property bool reachable: root.devices.length > 0
    // The one predicate both hosts read, so a tile cannot appear on one
    // edge and not the other.
    readonly property bool available: root.enabled && root.reachable

    // Exit 127 is the guard below saying kdeconnect-cli is not installed,
    // which is an ordinary state on a machine that never wanted it, not a
    // failure to report.
    property bool toolPresent: false
    property string lastError: ""
    property int spawns: 0

    function refresh(): void {
        if (!root.enabled || scan.running)
            return;
        root.spawns += 1;
        scan.running = true;
    }

    // Turning the flag on is also the moment a persisted true arrives from
    // settings.json, since Settings assigns after construction.
    onEnabledChanged: {
        if (root.enabled)
            root.refresh();
    }

    Process {
        id: scan

        // `command -v` before the launch, so a machine without KDE Connect
        // exits 127 instead of failing to start. That is what keeps the
        // package out of both base profiles: tests/test_profiles_shell_deps.py
        // treats a binary behind its own guard as optional by design. The
        // braces keep the guard's own exit code out of that same scan, which
        // reads the first word of every shell segment as a binary name.
        command: ["sh", "-c", "command -v kdeconnect-cli >/dev/null 2>&1 || { exit 127; }; exec kdeconnect-cli --list-available --id-name-only"]

        stdout: StdioCollector {
            id: scanOut

            onStreamFinished: root.devices = Policy.parseDevices(scanOut.text)
        }

        onExited: (code, status) => {
            root.toolPresent = code !== 127;
            root.lastError = (code === 0 || code === 127) ? "" : String(code);
        }
    }
}
