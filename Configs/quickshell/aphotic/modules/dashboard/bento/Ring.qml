pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.components
import qs.config
import qs.services

// An arc meter that sweeps to its value, with the figure in the middle.
Item {
    id: root

    property real value: 0
    property string figure: ""
    property string caption: ""
    property color colour: Colours.signal

    readonly property real size: Math.min(root.width, root.height)
    readonly property real thickness: Math.max(4, root.size * 0.065)
    property real shown: root.value

    Behavior on shown {
        NumberAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }
    }

    Shape {
        anchors.centerIn: parent
        width: root.size
        height: root.size
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Colours.signalStyle.hairline
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.size / 2
                centerY: root.size / 2
                radiusX: root.size / 2 - root.thickness
                radiusY: radiusX
                startAngle: 135
                sweepAngle: 270
            }
        }

        ShapePath {
            strokeColor: root.shown >= 0.9 ? Colours.palette.m3error : root.colour
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.size / 2
                centerY: root.size / 2
                radiusX: root.size / 2 - root.thickness
                radiusY: radiusX
                startAngle: 135
                sweepAngle: 270 * Math.max(0.001, Math.min(1, root.shown))
            }
        }
    }

    Column {
        anchors.centerIn: parent

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.figure
            color: Colours.ink
            font.family: Tokens.font.headline.large.family
            font.pixelSize: Math.max(14, root.size * 0.24)
            font.weight: Font.Light
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.caption !== ""
            text: root.caption
            color: Colours.inkMuted
            font.family: Tokens.font.mono.small.family
            font.pixelSize: Math.max(10, root.size * 0.085)
        }
    }
}
