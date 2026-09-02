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
    property real glowBlur: 18
    property real glowSpread: 0.06
    // Off for one-shot uses (e.g. the notification arrival flash) that
    // drive `intensity` themselves -- those own the whole curve and the
    // shared pulse would fight it. (This used to matter more: the old
    // animation assigned `opacity` imperatively, which permanently broke
    // the binding the moment it started. A binding cannot do that.)
    property bool breathing: true

    anchors.fill: target
    radius: Tokens.rounding.full
    color: Qt.alpha(root.glowColour, 0.65)
    blur: root.glowBlur
    spread: root.glowSpread
    offset.x: 0
    offset.y: 0
    visible: root.intensity > 0

    // Driven off DepthFx's shared clock rather than a per-instance
    // animation -- see that file for why, and for the numbers. Gated on
    // `visible` as well as `breathing` so a glow whose host is hidden
    // (HoverPill's, at idle) does not take a dependency on the clock at
    // all: a conditional binding only tracks the branch it evaluates, so
    // an invisible glow is dirtied by nothing.
    opacity: root.breathing && root.visible ? root.intensity * (0.45 + 0.55 * DepthFx.pulse) : root.intensity

    Behavior on color {
        CAnim {}
    }

}
