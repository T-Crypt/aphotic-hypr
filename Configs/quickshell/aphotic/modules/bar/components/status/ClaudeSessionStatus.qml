import QtQuick
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

        // Stays theme-consistent (matches every sibling status icon --
        // Bluetooth/network/resources/battery never recolor for "active",
        // only ever shift to m3error for a warning state) rather than
        // switching to m3primary, which reads as dull/gray against this
        // codebase's themes where secondaryOnSurface is the vivid tone.
        // The count badge below is the "something's running" signal.
        animate: true
        text: "smart_toy"
        color: root.colour
        fill: ClaudeSessions.count > 0 ? 1 : 0
    }

    StyledRect {
        visible: ClaudeSessions.count > 1

        anchors.top: icon.top
        anchors.right: icon.right
        anchors.topMargin: -Tokens.spacing.extraSmall / 2
        anchors.rightMargin: -Tokens.spacing.extraSmall / 2

        implicitWidth: Math.max(count.implicitWidth + Tokens.padding.extraSmall, Tokens.spacing.medium)
        implicitHeight: Tokens.spacing.medium
        radius: Tokens.rounding.full
        color: Colours.palette.m3primary

        StyledText {
            id: count

            anchors.centerIn: parent
            text: ClaudeSessions.count > 9 ? "9+" : String(ClaudeSessions.count)
            font: Tokens.font.label.small
            color: Colours.palette.m3onPrimary
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -Tokens.padding.small
        cursorShape: Qt.PointingHandCursor
        onClicked: ClaudeSessions.focusSession()
    }
}
