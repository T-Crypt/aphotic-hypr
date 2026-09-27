pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// Idle deliberately carries no clock: the bar already owns one in every
// style that shows the time, and a second one two centimetres away is just
// a duplicate. What is left is the smallest useful affordance -- live CPU
// and memory, off SystemUsage's always-running base poll, so idle costs
// nothing extra.
//
// When the Resource Engine has something worth saying under the current
// runtime context (ResourcePosture.surfaced), the two gauges give way to
// one: the resource that needs attention, in the posture's colour. The
// strip returns to CPU and memory once the posture settles.
GridLayout {
    id: root

    // Side-docked bars leave a strip only as wide as the bar is thick, so
    // the same content stacks down it instead of running off both ends
    // into dead, unclickable space.
    property bool stacked: false
    property bool attention: false

    readonly property bool posture: ResourcePosture.surfaced && ResourcePosture.resource !== null

    flow: root.stacked ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rowSpacing: Tokens.spacing.small
    columnSpacing: Tokens.spacing.small

    component MicroBar: StyledRect {
        id: microBar

        property real perc: 0
        property bool vertical: false
        property int length: 34
        property color barColour: Colours.palette.m3primary

        readonly property real fill: Math.max(0, Math.min(1, microBar.perc))

        implicitWidth: microBar.vertical ? 4 : microBar.length
        implicitHeight: microBar.vertical ? microBar.length : 4
        radius: Tokens.rounding.full
        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

        StyledRect {
            x: 0
            y: microBar.vertical ? microBar.height - height : 0
            width: microBar.vertical ? microBar.width : microBar.width * microBar.fill
            height: microBar.vertical ? microBar.height * microBar.fill : microBar.height
            radius: Tokens.rounding.full
            color: microBar.barColour
        }
    }

    MaterialIcon {
        Layout.alignment: Qt.AlignCenter
        text: root.posture ? "hub" : "monitoring"
        color: root.posture ? Colours.posture(ResourcePosture.level, Colours.palette.m3primaryOnSurface) : Colours.palette.m3primaryOnSurface
        fontStyle: Tokens.font.icon.small
        fill: 1
    }

    MicroBar {
        Layout.alignment: Qt.AlignCenter
        visible: !root.posture
        vertical: root.stacked
        perc: SystemUsage.cpuPerc
        barColour: Colours.palette.m3primary
    }

    MicroBar {
        Layout.alignment: Qt.AlignCenter
        visible: !root.posture
        vertical: root.stacked
        perc: SystemUsage.memPerc
        barColour: Colours.palette.m3tertiary
    }

    // Spans both gauges' footprint so the strip keeps its size.
    MicroBar {
        Layout.alignment: Qt.AlignCenter
        visible: root.posture
        vertical: root.stacked
        length: 34 * 2 + Tokens.spacing.small
        perc: ResourcePosture.resource?.ratio ?? 0
        barColour: Colours.posture(ResourcePosture.level, Colours.palette.m3primary)
    }

    StyledRect {
        Layout.alignment: Qt.AlignCenter
        implicitWidth: 6
        implicitHeight: 6
        radius: Tokens.rounding.full
        color: Colours.palette.m3primary
        visible: root.attention

        SequentialAnimation on opacity {
            running: root.attention && RenderGate.decorative
            loops: Animation.Infinite

            NumberAnimation {
                to: 0.35
                duration: 700
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                to: 1
                duration: 700
                easing.type: Easing.InOutQuad
            }
        }
    }
}
