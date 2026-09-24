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

    // The CLI reports failures as one coloured stderr line; strip the colour.
    function _firstLine(text: string): string {
        const lines = text.replace(/\u001B\[[0-9;]*m/g, "").split("\n")
            .filter(line => line.trim().length > 0);
        return lines.length > 0 ? lines[0].trim() : "";
    }

    function _finish(failTitle: string, exitCode: int, out: string, err: string): void {
        root.busy = false;
        if (exitCode !== 0) {
            const body = root._firstLine(err) || root._firstLine(out)
                || qsTr("exited with code %1").arg(exitCode);
            Toaster.toast(failTitle, body, "error");
            return;
        }
        // openvpn daemonizes and can still fail on auth, so show the CLI's
        // line (it names the log) on success too.
        const line = root._firstLine(out);
        if (line.length > 0)
            Toaster.toast(qsTr("VPN"), line, "vpn_key");
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

        stdout: StdioCollector {
            id: connectStdout
        }

        stderr: StdioCollector {
            id: connectStderr
        }

        onExited: exitCode => {
            root._finish(qsTr("VPN connect failed"), exitCode, connectStdout.text, connectStderr.text);
        }
    }

    Process {
        id: disconnectProc

        stdout: StdioCollector {
            id: disconnectStdout
        }

        stderr: StdioCollector {
            id: disconnectStderr
        }

        onExited: exitCode => {
            root._finish(qsTr("VPN disconnect failed"), exitCode, disconnectStdout.text, disconnectStderr.text);
        }
    }
}
