import QtQuick
import qs.config
import qs.components
import qs.services

MaterialIcon {
    id: root

    required property color colour
    required property ScreenState screenState

    text: "history"
    color: NotificationHistory.unreadCount > 0 ? Colours.palette.m3primary : root.colour
    fill: NotificationHistory.unreadCount > 0 ? 1 : 0

    MouseArea {
        anchors.fill: parent
        anchors.margins: -Tokens.padding.small
        cursorShape: Qt.PointingHandCursor
        onClicked: root.screenState.notificationCenter = !root.screenState.notificationCenter
    }
}
