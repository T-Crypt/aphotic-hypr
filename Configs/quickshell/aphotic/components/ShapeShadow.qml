import QtQuick
import QtQuick.Effects
import qs.services

// A drop shadow cast by a shape instead of by content.
//
// The obvious way to give a surface a shadow is `layer.enabled` on the
// surface itself with a MultiEffect. That makes the shadow correct and
// every repaint expensive: the whole surface is rendered to a texture and
// pushed through a five-level blur pyramid every time anything inside it
// changes, down to a clock digit or a CPU bar. Measured on an idle
// desktop, the shell's chrome was running 337 scene renders a second that
// way, ten of them blur-pyramid levels belonging to two windows nobody
// was touching.
//
// A drop shadow only depends on the silhouette. This draws the silhouette
// on its own, blurs that, and caches it until the geometry, radius or
// colour changes. The surface's real content then draws on top as plain
// quads, so a clock tick costs a clock tick.
//
// Sits inside the surface at `z: -1` with the surface's own radius and
// colour. It repaints the same opaque rounded rect the surface already
// draws, which costs one quad and looks identical.
Item {
    id: root

    property real radius: 0
    property color color: "transparent"
    property color shadowColor: Colours.palette.m3shadow
    property real shadowOpacity: 0.5
    property real shadowBlur: 0.5
    property real shadowVerticalOffset: 2

    z: -1

    Rectangle {
        id: shape
        anchors.fill: parent
        radius: root.radius
        color: root.color

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.shadowColor
            shadowOpacity: root.shadowOpacity
            shadowBlur: root.shadowBlur
            shadowVerticalOffset: root.shadowVerticalOffset
        }
    }
}
