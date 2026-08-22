import QtQuick
import QtQuick.Shapes
import qs.config
import qs.components
import qs.services

StyledRect {
    id: root

    implicitWidth: Settings.barInnerWidth
    implicitHeight: Settings.barInnerWidth

    color: Colours.palette.m3surfaceContainerHigh
    radius: Tokens.rounding.full

    Shape {
        readonly property real designSize: 88

        anchors.centerIn: parent
        width: designSize
        height: designSize
        scale: (root.implicitWidth - Tokens.padding.small * 2) / designSize
        transformOrigin: Item.Center
        preferredRendererType: Shape.CurveRenderer

        // Corner brackets, coloured to match Logo.qml's bottomColour role.
        ShapePath {
            fillColor: "transparent"
            strokeColor: Colours.palette.m3onSurface
            strokeWidth: 4.5
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg { path: "M20 58 L20 68 L30 68" }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: Colours.palette.m3onSurface
            strokeWidth: 4.5
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg { path: "M68 30 L68 20 L58 20" }
        }

        // Crescent moon, coloured to match Logo.qml's topColour role. The
        // two circle subpaths combine via the default odd-even fill rule
        // into the crescent cutout, same as the source SVG's evenodd fill.
        ShapePath {
            fillColor: Colours.palette.m3primary
            strokeColor: "transparent"

            PathSvg {
                path: "M 26,44 a 18,18 0 1,0 36,0 a 18,18 0 1,0 -36,0 Z M 36.5,44 a 13.5,13.5 0 1,0 27,0 a 13.5,13.5 0 1,0 -27,0 Z"
            }
        }
    }
}
