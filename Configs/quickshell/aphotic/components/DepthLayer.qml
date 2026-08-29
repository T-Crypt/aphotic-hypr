pragma ComponentBehavior: Bound

import QtQuick
import qs.services

// Ambient "marine snow" -- a handful of soft, slow-drifting particles meant
// to sit behind a popout's real content, never in front of it. Cheap by
// construction: one linear NumberAnimation per particle, no physics, count
// capped by services/DepthFx.qml's tier (0 when Depth Effects is off).
//
// `opacityScale` is how a host surface dials the field down (or skips it
// entirely by not instantiating this at all) when its own content is
// already visually dense -- see the per-surface usage sites for the actual
// values chosen.
Item {
    id: root

    property color particleColour: Colours.palette.m3primary
    property int count: DepthFx.particleCount
    property real opacityScale: 1

    clip: true
    visible: root.count > 0

    Repeater {
        model: root.visible ? root.count : 0

        Rectangle {
            id: particle

            required property int index

            readonly property real particleSize: 1.5 + Math.random() * 2.5
            readonly property real driftDuration: 14000 + Math.random() * 12000

            width: particleSize
            height: particleSize
            radius: particleSize / 2
            color: root.particleColour
            opacity: (0.08 + Math.random() * 0.2) * root.opacityScale
            x: Math.random() * Math.max(1, root.width)
            y: Math.random() * Math.max(1, root.height)

            SequentialAnimation {
                running: root.visible
                loops: Animation.Infinite

                NumberAnimation {
                    target: particle
                    property: "y"
                    to: -particle.particleSize * 4
                    duration: particle.driftDuration
                    easing.type: Easing.Linear
                }
                PropertyAction {
                    target: particle
                    property: "y"
                    value: root.height + particle.particleSize * 4
                }
            }
        }
    }
}
