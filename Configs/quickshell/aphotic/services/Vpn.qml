pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Status/connect/disconnect for the raw-openvpn profile `aphotic vpn`
// manages (see commands/cmd_vpn.sh's own header comment) -- deliberately
// separate from Nmcli.qml's `vpnActive`, which reflects NetworkManager's
// own VPN connection list, a different mechanism this doesn't touch.
//
// Status is read directly here (pgrep, same distinctive --daemon tag
// cmd_vpn.sh uses, no sudo needed) rather than parsing `aphotic vpn
// status`'s human-oriented colored output -- connect()/disconnect() are
// the only two actions that actually need root, so those are the only
// two that shell out to the CLI (keeps privileged process management in
// bash, QML just reflects live state, per ROADMAP_FEATURES.md PART C).
Singleton {
    id: root

    readonly property string daemonTag: "aphotic-vpn"

    property bool connected: false
    property bool busy: false

    function refresh(): void {
        statusProc.exec(["pgrep", "-f", root.daemonTag]);
    }

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

    Process {
        id: statusProc
        stdout: StdioCollector {
            onStreamFinished: root.connected = text.trim().length > 0
        }
    }

    Process {
        id: connectProc
        onExited: {
            root.busy = false;
            root.refresh();
        }
    }

    Process {
        id: disconnectProc
        onExited: {
            root.busy = false;
            root.refresh();
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
