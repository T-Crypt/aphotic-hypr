import QtQuick
import QtQuick.Effects
import qs.config
import qs.components
import qs.services

// The shared "alive" glow -- a soft, theme-accent-coloured blur that
// breathes rather than sitting at a flat static opacity. Every focused/
// active/interactive indicator this repo adds under the Aphotic Depth
// treatment uses this instead of inventing its own highlight or its own
// pulse rhythm (see services/DepthFx.qml for the shared cadence/intensity).
//
// Declare this as a SIBLING of `target`, BEFORE it in z-order (earlier in
// the file) -- like Elevation.qml's RectangularShadow, it renders a blurred
// shape sized to `target`'s own bounds, and `target` needs to paint on top
// to hide the solid core, leaving only the soft bleed around its edges
// visible.
RectangularShadow {
    id: root

    required property Item target
    property color glowColour: Colours.palette.m3primary
    property real intensity: DepthFx.glowIntensity
    property int pulsePeriod: DepthFx.pulsePeriod
    property real glowBlur: 18
    property real glowSpread: 0.06
    // Off for one-shot uses (e.g. the notification arrival flash) that
    // drive `intensity` themselves via their own animation -- the
    // breathing loop below targets `opacity` directly, which would
    // otherwise permanently break the `opacity: root.intensity` binding
    // the moment it starts and fight the caller's own decay curve.
    property bool breathing: true

    anchors.fill: target
    radius: Tokens.rounding.full
    color: Qt.alpha(root.glowColour, 0.65)
    blur: root.glowBlur
    spread: root.glowSpread
    offset.x: 0
    offset.y: 0
    visible: root.intensity > 0
    opacity: root.intensity

    Behavior on color {
        CAnim {}
    }

    SequentialAnimation {
        running: root.visible && root.breathing
        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "opacity"
            from: root.intensity * 0.45
            to: root.intensity
            duration: root.pulsePeriod
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "opacity"
            from: root.intensity
            to: root.intensity * 0.45
            duration: root.pulsePeriod
            easing.type: Easing.InOutSine
        }
    }
}
