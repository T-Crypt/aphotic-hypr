pragma ComponentBehavior: Bound

import QtQuick
import qs.services

// The Signal skin's base surface: the raised bar tone, a hairline border,
// and a 1px edge-light line along the top (inset by the radius, like the
// cards in FlowScene.qml). Depth comes from those two lines, never a shadow.
Rectangle {
    id: root

    // Override to re-tint a specific surface (e.g. Minimal's translucent
    // bar); leave unset for the default signal tone.
    property color tone: Colours.signalStyle.bar

    color: root.tone
    border.width: 1
    border.color: Colours.signalStyle.hairline

    Rectangle {
        x: parent.radius
        width: parent.width - parent.radius * 2
        height: 1
        color: Colours.signalStyle.edgeLight
    }
}
