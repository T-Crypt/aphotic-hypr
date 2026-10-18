pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// The dashboard's one tile: dark glass, a hairline that warms toward the
// accent under the pointer, light along the top edge, and a header with an
// icon, a label and an optional figure. `live` lights a small dot beside
// the label while the tile's subject is doing something. Content goes in
// the body and is given all the room left under the header.
Item {
    id: root

    property string icon: ""
    property string label: ""
    property string figure: ""
    property bool live: false
    property bool accent: false
    property real padding: Tokens.padding.large

    default property alias body: content.data
    readonly property bool hovered: hover.hovered
    readonly property real headerHeight: header.visible ? header.implicitHeight + Tokens.spacing.small : 0

    Rectangle {
        id: glass

        anchors.fill: parent
        radius: Tokens.rounding.large
        color: root.hovered ? Colours.signalStyle.raised : Qt.alpha(Colours.signalStyle.surface, 0.72)
        border.width: 1
        border.color: root.accent ? Qt.alpha(Colours.signal, 0.65) : (root.hovered ? Qt.alpha(Colours.signal, 0.42) : Colours.signalStyle.hairline)

        Behavior on color {
            CAnim {}
        }

        Behavior on border.color {
            CAnim {}
        }

        Rectangle {
            x: glass.radius
            width: parent.width - glass.radius * 2
            height: 1
            color: Colours.signalStyle.edgeLight
        }
    }

    RowLayout {
        id: header

        visible: root.label !== "" || root.icon !== ""
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.padding
        spacing: Tokens.spacing.small

        MaterialIcon {
            visible: root.icon !== ""
            text: root.icon
            color: root.live || root.accent ? Colours.signal : Colours.inkMuted
            fontStyle: Tokens.font.icon.small
        }

        StyledText {
            text: root.label.toUpperCase()
            color: Colours.inkMuted
            font: Tokens.font.label.builders.small.weight(Font.Medium).letterSpacing(1.2).build()
        }

        Rectangle {
            visible: root.live
            implicitWidth: 6
            implicitHeight: 6
            radius: 3
            color: Colours.signal

            SequentialAnimation on opacity {
                running: root.live && RenderGate.decorative && root.visible
                loops: Animation.Infinite
                alwaysRunToEnd: true

                NumberAnimation {
                    to: 0.25
                    duration: 900
                    easing.type: Easing.InOutSine
                }

                NumberAnimation {
                    to: 1
                    duration: 900
                    easing.type: Easing.InOutSine
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }

        StyledText {
            visible: root.figure !== ""
            text: root.figure
            color: Colours.ink
            font: Tokens.font.mono.small
        }
    }

    Item {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.top: header.visible ? header.bottom : parent.top
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        anchors.bottomMargin: root.padding
        anchors.topMargin: header.visible ? Tokens.spacing.small : root.padding
    }

    HoverHandler {
        id: hover
    }
}
