import QtQuick
import QtQuick.Effects
import qs.services

Item {
    id: root

    required property Item target
    property int level: 2

    readonly property real blur: level === 1 ? 8 : level === 2 ? 14 : 22
    readonly property real offsetY: level === 1 ? 1 : level === 2 ? 2 : 4
    readonly property real levelOpacity: level === 1 ? 0.35 : level === 2 ? 0.45 : 0.55

    property real radius: root.target.radius
    property real topLeftRadius: root.radius
    property real topRightRadius: root.radius
    property real bottomLeftRadius: root.radius
    property real bottomRightRadius: root.radius

    // Either a sibling placed before the target, or a child of the target
    // (for targets inside a layout); a child with negative z draws below it.
    readonly property bool inside: root.parent === root.target

    z: inside ? -1 : 0

    RectangularShadow {
        x: root.inside ? 0 : root.target.x
        y: root.inside ? 0 : root.target.y
        width: root.target.width
        height: root.target.height
        radius: root.radius
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        blur: root.blur
        offset: Qt.vector2d(0, root.offsetY)
        color: Colours.palette.m3shadow
        opacity: root.inside ? root.levelOpacity : root.target.opacity * root.levelOpacity
        scale: root.inside ? 1 : root.target.scale
        transformOrigin: root.target.transformOrigin
        cached: true
    }
}
