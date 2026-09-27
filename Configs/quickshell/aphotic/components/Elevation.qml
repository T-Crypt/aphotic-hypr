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

    RectangularShadow {
        x: root.target.x
        y: root.target.y
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
        opacity: root.target.opacity * root.levelOpacity
        cached: true
    }
}
