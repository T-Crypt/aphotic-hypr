pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components
import qs.services

// The visible shelf handle. It is the whole affordance a closed edge has:
// its own bounds, no edge pressure, no sensor, and a click that reveals
// through the same path the shortcut does.
Item {
    id: root

    required property string edge
    signal clicked

    readonly property bool hovered: hover.hovered
    readonly property real radius: Tokens.rounding.full

    StyledRect {
        anchors.fill: parent
        radius: root.radius
        color: root.hovered ? Colours.layer(Colours.palette.m3onSurface, 0.12)
            : Colours.layer(Colours.palette.m3onSurface, 0.06)
        Behavior on color {
            enabled: RenderGate.decorative
            CAnim {}
        }
    }

    MouseArea {
        objectName: "shelf-handle-click"
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    HoverHandler { id: hover }
}