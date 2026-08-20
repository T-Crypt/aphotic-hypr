import QtQuick
import qs.components
import qs.config
import qs.services

Item {
    id: root

    required property var screen
    required property int barWidth
    property bool hasCurrent: false
    property string currentName: ""
    property real currentCenter: 0

    readonly property string content: {
        switch (currentName) {
        case "statusIcons": return "Status";
        case "tray": return "Tray";
        case "activeWindow": return "Window";
        default: return currentName.startsWith("traymenu") ? "Tray item" : "";
        }
    }

    StyledRect {
        id: flyout
        visible: root.hasCurrent
        x: root.barWidth + Tokens.spacing.small
        y: Math.max(0, root.currentCenter - height / 2)
        width: 160
        height: label.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainerHigh

        StyledText {
            id: label
            anchors.centerIn: parent
            text: root.content
        }
    }
}
