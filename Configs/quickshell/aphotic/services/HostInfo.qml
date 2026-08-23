pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Hostname + primary LAN IP, polled here and shared by the bar's
// HostInfoStatus icon and its popout -- same "one service, icon + popout
// both read it" shape as ClaudeSessions. Aimed at SSH-heavy workflows:
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

    Component.onCompleted: hostnameProc.exec(["uname", "-n"])

    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: ipProc.exec(["ip", "route", "get", "1.1.1.1"])
    }
}
