import QtQuick
import qs.config
import qs.components
import qs.services

MaterialIcon {
    id: root

    required property color colour

    animate: true
    text: Pomodoro.isBreak ? "coffee" : "timer"
    color: root.colour
    fill: Pomodoro.running ? 1 : 0

    MouseArea {
        anchors.fill: parent
        anchors.margins: -Tokens.padding.small
        cursorShape: Qt.PointingHandCursor
        onClicked: Pomodoro.toggle()
    }
}
