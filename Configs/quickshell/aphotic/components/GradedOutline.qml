import QtQuick
import QtQuick.Shapes
import qs.config
import qs.services

// A 1px rim that is brighter on the top edge than the bottom one. A ShapePath
// stroke takes no gradient, so the rim is the band between two rounded rects.
Shape {
    id: root

    property real radius: 0
    property real topLeftRadius: radius
    property real topRightRadius: radius
    property real bottomLeftRadius: radius
    property real bottomRightRadius: radius
    property real weight: 1

    // 0 container, 1 row or card, 2 control.
    property int level: 1
    property bool hovered: false
    property bool accent: false
    property color accentColour: Colours.palette.m3primary
    // Consumers gate the rim through this rather than `visible`: `visible`
    // carries the degenerate-size guard below, and overriding it leaves a
    // collapsed delegate rendering a solid gradient block instead of a rim.
    property bool showRim: true

    readonly property real _lit: [0.10, 0.13, 0.18][Math.max(0, Math.min(2, root.level))] + (root.hovered ? 0.08 : 0)
    readonly property real _shade: [0.035, 0.045, 0.07][Math.max(0, Math.min(2, root.level))] + (root.hovered ? 0.03 : 0)

    property color topColour: root.accent ? Qt.alpha(root.accentColour, 0.9) : Qt.alpha(Colours.palette.m3onSurface, root._lit)
    property color bottomColour: root.accent ? Qt.alpha(root.accentColour, 0.4) : Qt.alpha(Colours.palette.m3onSurface, root._shade)

    function _clamp(r: real, inset: real): real {
        return Math.max(0, Math.min(r, root.width / 2, root.height / 2) - inset);
    }

    Behavior on topColour {
        CAnim {}
    }
    Behavior on bottomColour {
        CAnim {}
    }

    anchors.fill: parent
    visible: root.showRim && width > root.weight * 2 && height > root.weight * 2
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillRule: ShapePath.OddEvenFill
        fillGradient: LinearGradient {
            x1: 0
            y1: 0
            x2: 0
            y2: root.height

            GradientStop {
                position: 0
                color: root.topColour
            }
            GradientStop {
                position: 1
                color: root.bottomColour
            }
        }

        PathRectangle {
            x: 0
            y: 0
            width: root.width
            height: root.height
            topLeftRadius: root._clamp(root.topLeftRadius, 0)
            topRightRadius: root._clamp(root.topRightRadius, 0)
            bottomLeftRadius: root._clamp(root.bottomLeftRadius, 0)
            bottomRightRadius: root._clamp(root.bottomRightRadius, 0)
        }
        PathRectangle {
            x: root.weight
            y: root.weight
            width: Math.max(0, root.width - root.weight * 2)
            height: Math.max(0, root.height - root.weight * 2)
            topLeftRadius: root._clamp(root.topLeftRadius, root.weight)
            topRightRadius: root._clamp(root.topRightRadius, root.weight)
            bottomLeftRadius: root._clamp(root.bottomLeftRadius, root.weight)
            bottomRightRadius: root._clamp(root.bottomRightRadius, root.weight)
        }
    }
}
