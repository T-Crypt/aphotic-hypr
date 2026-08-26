import QtQuick
import qs.config
import qs.components
import qs.services

MaterialIcon {
    id: root

    required property color colour

    text: DoNotDisturb.enabled ? "notifications_off" : "notifications"
    color: root.colour
    fill: DoNotDisturb.enabled ? 1 : 0

    MouseArea {
        anchors.fill: parent
        anchors.margins: -Tokens.padding.small
        cursorShape: Qt.PointingHandCursor
        onClicked: DoNotDisturb.toggle()
    }
}
