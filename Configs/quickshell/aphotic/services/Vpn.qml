pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Status/connect/disconnect for the raw-openvpn profile `aphotic vpn`
// manages (see commands/cmd_vpn.sh's own header comment) -- deliberately
// separate from Nmcli.qml's `vpnActive`, which reflects NetworkManager's
// own VPN connection list, a different mechanism this doesn't touch.
//
// Status is a marker file openvpn's own --up/--down hooks write
// (lib/aphotic/vpn-hook.sh), watched here, so this singleton costs
// nothing while idle. It used to be a 5s `pgrep` on a Timer, which ran
// for the whole session whether or not a tunnel existed -- the same
// zero-idle-cost rule the Gaming profile's dbus-monitor DETECT follows.
// A missing marker is the disconnected state, not an error, which is why
// onLoadFailed is a normal branch here.
//
// connect()/disconnect() are the only two actions that need root, so
// they stay the only two that shell out to the CLI (privileged process
// management in bash, QML reflecting live state, per ROADMAP_FEATURES.md
// PART C).
Singleton {
    id: root

    readonly property string markerPath: `${Quickshell.env("HOME")}/.local/state/aphotic/vpn-connected`

    property bool connected: false
    property bool busy: false

    function connectVpn(configPath: string): void {
        root.busy = true;
        const args = ["aphotic", "vpn", "connect"];
        if (configPath)
            args.push(configPath);
        connectProc.exec(args);
    }

    function disconnectVpn(): void {
        root.busy = true;
        disconnectProc.exec(["aphotic", "vpn", "disconnect"]);
    }

    FileView {
        path: root.markerPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.connected = true
        onLoadFailed: root.connected = false
    }

    Process {
        id: connectProc
        onExited: root.busy = false
    }

    Process {
        id: disconnectProc
        onExited: root.busy = false
    }
}
