import QtQuick
import qs.components
import qs.config
import qs.services

// A pair of light heads that run from the bottom centre of the frame, along
// the bottom band and up both sides toward the bar. It plays once per
// surface change and never loops.
Item {
    id: root

    required property real band
    required property real topInset

    property real progress: 0

    readonly property real half: root.width / 2
    readonly property real rise: Math.max(0, root.height - root.topInset)
    readonly property real travel: root.half + root.rise
    readonly property real at: root.progress * root.travel
    readonly property bool onBottom: root.at < root.half
    readonly property real headLength: 96

    function run(): void {
        if (!RenderGate.decorative || !Config.hull.sweep || root.width <= 0)
            return;
        anim.restart();
    }

    anchors.fill: parent
    visible: anim.running

    NumberAnimation {
        id: anim

        target: root
        property: "progress"
        from: 0
        to: 1
        duration: Tokens.anim.durations.expressiveSlowSpatial * 2
        easing.type: Easing.InOutCubic
    }

    Repeater {
        model: 2

        Rectangle {
            id: head

            required property int index

            readonly property bool mirrored: head.index === 1
            readonly property bool leadsAtEnd: root.onBottom && head.mirrored

            x: root.onBottom ? (head.mirrored ? root.half + root.at - width : root.half - root.at) : (head.mirrored ? root.width - root.band : 0)
            y: root.onBottom ? root.height - root.band : root.height - (root.at - root.half) - height
            width: root.onBottom ? root.headLength : root.band
            height: root.onBottom ? root.band : root.headLength
            opacity: 1 - Math.max(0, root.progress - 0.8) / 0.2

            gradient: Gradient {
                orientation: root.onBottom ? Gradient.Horizontal : Gradient.Vertical

                GradientStop {
                    position: 0
                    color: head.leadsAtEnd ? Qt.alpha(Colours.signalStyle.accentLine, 0) : Colours.signalStyle.accentLine
                }
                GradientStop {
                    position: 1
                    color: head.leadsAtEnd ? Colours.signalStyle.accentLine : Qt.alpha(Colours.signalStyle.accentLine, 0)
                }
            }
        }
    }
}
