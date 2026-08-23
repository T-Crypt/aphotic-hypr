import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property color colour

    implicitWidth: icon.implicitWidth
    implicitHeight: icon.implicitHeight

    MaterialIcon {
        id: icon

        animate: true
        text: "lan"
        color: root.colour
        fill: HostInfo.ipAddress.length > 0 ? 1 : 0
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -Tokens.padding.small
        cursorShape: Qt.PointingHandCursor
        enabled: HostInfo.ipAddress.length > 0
        onClicked: {
            Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", HostInfo.ipAddress]);
            Quickshell.execDetached(["notify-send", "-a", "aphotic", "IP address copied", HostInfo.ipAddress]);
        }
    }
}
