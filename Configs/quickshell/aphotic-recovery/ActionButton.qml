// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

import QtQuick

Rectangle {
    id: root

    property string label
    property string detail
    property bool primary: false
    property bool enabledAction: true

    signal activated

    implicitHeight: column.implicitHeight + 24
    radius: 10
    color: !root.enabledAction ? Colours.surface : root.primary ? Colours.primary : mouse.containsMouse ? Colours.surfaceRaised : Colours.surface
    border.width: 1
    border.color: root.primary ? "transparent" : Colours.outline
    opacity: root.enabledAction ? 1 : 0.45

    Behavior on color {
        ColorAnimation {
            duration: 120
        }
    }

    Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        spacing: 3

        Text {
            width: parent.width
            text: root.label
            color: root.primary ? Colours.primaryTextColor : Colours.textColor
            font.pixelSize: 15
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            visible: root.detail.length > 0
            text: root.detail
            color: root.primary ? Colours.primaryTextColor : Colours.mutedTextColor
            font.pixelSize: 12
            opacity: root.primary ? 0.75 : 1
            wrapMode: Text.WordWrap
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabledAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.enabledAction)
                root.activated();
        }
    }
}
