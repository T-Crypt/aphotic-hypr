import QtQuick
import qs.services

// A structural lighting cue, not a palette addition: very slightly lighter
// toward the near/top edge of a surface, darker toward the far/bottom edge,
// both derived from that surface's own existing background colour. Meant
// as a thin overlay on top of an already-painted background rect (same
// radius, mouse-transparent), not a replacement for its `color`.
Rectangle {
    id: root

    property color baseColour: Colours.tPalette.m3surfaceContainer
    property real strength: 0.05

    color: "transparent"

    gradient: Gradient {
        GradientStop {
            position: 0

            color: Qt.tint(root.baseColour, Qt.alpha("#ffffff", root.strength))

            Behavior on color {
                CAnim {}
            }
        }
        GradientStop {
            position: 1

            color: Qt.tint(root.baseColour, Qt.alpha("#000000", root.strength))

            Behavior on color {
                CAnim {}
            }
        }
    }
}
