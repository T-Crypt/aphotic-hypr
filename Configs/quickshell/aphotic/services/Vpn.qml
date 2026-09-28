pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "VpnCore.js" as Core

// Every VPN type is an adapter behind one contract in cmd_vpn.sh; this
// singleton reads `aphotic vpn list --json` and aggregates it, and every
// VPN surface reads it from here. Actions shell out to the same CLI
// (privileged process management in bash, QML reflecting live state).
// The list is re-read on the OpenVPN marker changing, after an action and
// on refresh() from a surface that opens, never on a timer.
//
// `connected` is the raw OpenVPN profile's marker alone, written by
// openvpn's own --up/--down hooks (lib/aphotic/vpn-hook.sh). A missing
// marker is the disconnected state, not an error, which is why
// onLoadFailed is a normal branch here.
Singleton {
    id: root

    readonly property string markerPath: `${Quickshell.env("HOME")}/.local/state/aphotic/vpn-connected`

    property bool connected: false
    property bool busy: false

    property var providers: []
    readonly property var connections: Core.connections(root.providers)
    readonly property var activeConnections: Core.active(root.providers)
    readonly property var status: Core.status(root.providers)
    property bool _refreshAgain: false

    function refresh(): void {
        if (listProc.running)
            root._refreshAgain = true;
        else
            listProc.running = true;
    }

    function list(): var {
        return root.connections;
    }

    function connectionOf(provider: string, id: string): var {
        return root.connections.find(c => c.provider === provider && c.id === id) ?? null;
    }

    function connectProvider(provider: string, id: string): void {
        root._providerAction("connect", provider, id);
    }

    function disconnectProvider(provider: string, id: string): void {
        root._providerAction("disconnect", provider, id);
    }

    function _providerAction(action: string, provider: string, id: string): void {
        if (root.busy || !provider)
            return;
        root.busy = true;
        const args = ["aphotic", "vpn", action, "--provider", provider];
        if (id)
            args.push(id);
        actionProc.failTitle = action === "connect" ? qsTr("VPN connect failed") : qsTr("VPN disconnect failed");
        actionProc.exec(args);
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
        root.refresh();
    }

    FileView {
        path: root.markerPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.connected = true;
            root.refresh();
        }
        onLoadFailed: {
            root.connected = false;
            root.refresh();
        }
    }

    Connections {
        target: Nmcli

        function onVpnActiveChanged(): void {
            root.refresh();
        }

        function onVpnConnectionNameChanged(): void {
            root.refresh();
        }
    }

    Process {
        id: listProc

        command: ["aphotic", "vpn", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: root.providers = Core.parse(text)
        }
        onExited: {
            if (root._refreshAgain) {
                root._refreshAgain = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    Process {
        id: actionProc

        property string failTitle: ""

        stdout: StdioCollector {
            id: actionStdout
        }

        stderr: StdioCollector {
            id: actionStderr
        }

        onExited: exitCode => {
            root._finish(actionProc.failTitle, exitCode, actionStdout.text, actionStderr.text);
        }
    }

}
