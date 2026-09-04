pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.config
import qs.components
import qs.services

Item {
    id: root

    property real value: 0
    property string label
    property color accent: Colours.palette.m3primary
    property int diameter: 52
    property real thickness: 5

    readonly property real clamped: Math.max(0, Math.min(1, root.value))
    readonly property real ringRadius: (root.diameter - root.thickness) / 2

    implicitWidth: root.diameter
    implicitHeight: root.diameter

    Behavior on value {
        Anim { type: Anim.DefaultEffects }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.thickness
            strokeColor: Colours.layer(Colours.palette.m3surfaceContainerHigh, 4)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.diameter / 2
                centerY: root.diameter / 2
                radiusX: root.ringRadius
                radiusY: root.ringRadius
                startAngle: 130
                sweepAngle: 280
            }
        }

        ShapePath {
            strokeWidth: root.thickness
            strokeColor: root.accent
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.diameter / 2
                centerY: root.diameter / 2
                radiusX: root.ringRadius
                radiusY: root.ringRadius
                startAngle: 130
                sweepAngle: 280 * root.clamped
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: -2

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(root.clamped * 100)
            color: Colours.palette.m3onSurface
            font: Tokens.font.title.builders.small.weight(Font.Medium).build()
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.builders.small.scale(0.85).build()
        }
    }
}
