pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Hostname + primary LAN IP, polled here and shared by the bar's
// HostInfoStatus icon and its popout -- same "one service, icon + popout
// both read it" shape as AgentProviders. Aimed at SSH-heavy workflows:
// quick-copy either value without opening a terminal.
Singleton {
    id: root

    property string hostname: ""
    property string ipAddress: ""

    Process {
        id: hostnameProc

        // uname over hostname(1): coreutils is always present, whereas the
        // hostname binary ships in inetutils, which isn't guaranteed on a
        // minimal install.
        stdout: StdioCollector {
            onStreamFinished: root.hostname = text.trim()
        }
    }

    Process {
        id: ipProc

        stdout: StdioCollector {
            onStreamFinished: {
                // "1.1.1.1 via <gw> dev <if> src <ip> ..." -- a route-table
                // lookup, not an actual packet, so this works offline too.
                // Empty when there's no default route (no connection).
                const match = text.trim().match(/\bsrc (\S+)/);
                root.ipAddress = match ? match[1] : "";
            }
        }
    }

    Component.onCompleted: {
        hostnameProc.exec(["uname", "-n"]);
        ipRefresh.restart();
    }

    Connections {
        target: Nmcli
        function onActiveConnectionChanged() {
            ipRefresh.restart();
        }
        function onActiveInterfaceChanged() {
            ipRefresh.restart();
        }
        function onIsConnectedChanged() {
            ipRefresh.restart();
        }
    }

    Timer {
        id: ipRefresh
        interval: 1500
        onTriggered: ipProc.exec(["ip", "route", "get", "1.1.1.1"])
    }

    // A DHCP renewal or a VPN can move the address without changing the
    // active connection, so check now and then anyway.
    Timer {
        interval: 300000
        running: true
        repeat: true
        onTriggered: ipRefresh.restart()
    }
}
