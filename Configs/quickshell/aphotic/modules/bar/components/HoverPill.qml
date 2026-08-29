pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.components.effects
import qs.services

// The bar's shared hover affordance: one soft circle that GLIDES along a
// row/column of icons to sit behind whichever one the pointer is over,
// rather than each icon flashing its own separate highlight. Every bar
// style uses this same component so the feel is identical across Full,
// Taskbar, Dock and Minimal, and in all four dock orientations.
//
// Usage: put this as a SIBLING of the row/column holding the icons (it
// positions itself in that sibling's parent's coordinate space, offset by
// the container's own x/y), and feed it whichever child is hovered:
//
//     Item {
//         HoverPill {
//             container: icons
//             hoveredEntry: root.hoveredEntry
//             thickness: parent.height        // cross-axis room available
//         }
//         RowLayout { id: icons; ... }
//     }
//
// Resolve `hoveredEntry` with BarHit.nearestAlong() so the switch-over
// point between two adjacent icons is the same everywhere too.
StyledRect {
    id: root

    // The row/column whose children are the hover targets. `centerAlong`
    // and the x/y below are expressed in ITS coordinate space.
    required property Item container
    // Whichever child of `container` is currently under the pointer, or
    // null for none.
    required property Item hoveredEntry

    // Cross-axis room this pill has to fit inside -- the host pill/strip's
    // thickness, NOT the container's own. Those differ: a horizontal row of
    // icons is only one icon tall, so sizing off the container would shrink
    // the highlight to smaller than the icon it sits behind.
    property real thickness: Settings.barInnerWidth
    // How strongly the highlight reads. Matches the Material state-layer
    // hover opacity the rest of the shell uses.
    property real strength: 0.08

    readonly property real diameter: Math.max(0, Math.min(thickness, Settings.barInnerWidth) - Tokens.padding.extraSmall)

    // Centre of the hovered child along the bar's length, in `container`'s
    // coordinates. Animating this -- rather than the pill's x/y directly --
    // is what makes the highlight glide between neighbours instead of
    // reappearing at the new one.
    property real centerAlong

    visible: opacity > 0
    opacity: hoveredEntry ? strength : 0
    implicitWidth: diameter
    implicitHeight: diameter
    radius: diameter / 2
    color: Colours.palette.m3onSurface

    x: Settings.barHorizontal ? container.x + centerAlong - diameter / 2 : container.x + container.width / 2 - diameter / 2
    y: Settings.barHorizontal ? container.y + container.height / 2 - diameter / 2 : container.y + centerAlong - diameter / 2

    // A plain binding would snap `centerAlong` back to 0 the moment the
    // pointer leaves, dragging the pill to the start of the row on its way
    // out. Holding the last centre while it fades keeps the exit clean.
    Binding {
        target: root
        property: "centerAlong"
        value: root.hoveredEntry ? (Settings.barHorizontal ? root.hoveredEntry.x + root.hoveredEntry.width / 2 : root.hoveredEntry.y + root.hoveredEntry.height / 2) : 0
        when: root.hoveredEntry !== null
    }

    Behavior on centerAlong {
        Anim {
            type: Anim.FastEffects
        }
    }

    Behavior on opacity {
        Anim {
            type: Anim.FastEffects
        }
    }

    // The glow rides along for free -- it's anchored to root, and root's
    // own x/y glide is already animated above, so this reads as a soft
    // trail during motion rather than a separate effect to keep in sync.
    BioluminescentGlow {
        target: root
        glowBlur: 12
    }
}
