pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.utils
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen

    readonly property bool disabled: Strings.testRegexList(Config.bar.excludedScreens, screen.name)
    // Dock lives entirely in its own floating DockWindow (see
    // DockWindow.qml) -- this edge-docked strip has nothing to render
    // and must reserve no space while that style is active.
    readonly property bool hiddenMode: Settings.barVisibility === "hidden" || Settings.barStyle === "dock"
    // BarWindow.qml's input mask needs a wider hover target than root's
    // own (collapsed, in autohide mode) bounds -- content is already
    // always sized to the full contentWidth/height regardless of
    // collapse state (see below), it's just clipped visually by root's
    // own clip:true. Exposed so the window can mask to this instead of
    // root when it needs a real, hittable hover-to-reveal zone rather
    // than a literal couple-of-pixels sliver.
    readonly property alias hoverTarget: content

    readonly property int padding: Math.max(Tokens.padding.small, Config.border.thickness)
    readonly property int contentWidth: Settings.barInnerWidth + padding * 2
    // "hidden" reserves no desktop space at all, matching a fully disabled
    // bar; "autohide" still reserves the thin sliver so windows don't tile
    // into the space the reveal-on-hover strip occupies.
    readonly property int exclusiveZone: disabled || hiddenMode ? 0 : (Settings.barVisibility === "always" || screenState.bar ? contentWidth : Config.border.thickness)
    // "hidden" never reveals via hover -- isHovered only feeds visibility
    // in "autohide" mode, where the always-present sliver is the hover
    // target in the first place.
    readonly property bool shouldBeVisible: !fullscreen && !disabled && !hiddenMode && (Settings.barVisibility === "always" || screenState.bar || isHovered)
    property bool isHovered

    function closeTray(): void {
        (content.item as BarShell)?.closeTray();
    }

    function checkPopout(y: real): void {
        (content.item as BarShell)?.checkPopout(y);
    }

    function handleWheel(y: real, angleDelta: point): void {
        (content.item as BarShell)?.handleWheel(y, angleDelta);
    }

    clip: true
    // Anchor pairs decide which axis is actually screen-edge-driven (see
    // BarWindow.qml's own dual implicitWidth/implicitHeight comment) -- the
    // other axis is this collapsible thickness, whichever one that is.
    visible: (Settings.barHorizontal ? height : width) > 0
    implicitWidth: fullscreen || hiddenMode ? 0 : Config.border.thickness
    implicitHeight: fullscreen || hiddenMode ? 0 : Config.border.thickness

    states: State {
        name: "visible"
        when: root.shouldBeVisible

        PropertyChanges {
            root.implicitWidth: root.contentWidth
            root.implicitHeight: root.contentWidth
        }
    }

    transitions: [
        Transition {
            from: ""
            to: "visible"

            Anim {
                target: root
                properties: "implicitWidth,implicitHeight"
            }
        },
        Transition {
            from: "visible"
            to: ""

            Anim {
                target: root
                properties: "implicitWidth,implicitHeight"
                type: Anim.Emphasized
            }
        }
    ]

    // Both children hug the wrapper edge facing away from the docked
    // screen edge (i.e. towards the popout flyout's padding space in
    // BarWindow.qml) -- that's parent.right when docked left (screen edge
    // is parent.left, fixed at the window's own left) and parent.left when
    // docked right (screen edge is parent.right instead). This keeps the
    // visible strip flush against the true screen edge in both modes as
    // root's implicitWidth animates.
    //
    // Anchors are swapped via States + AnchorChanges rather than a plain
    // `anchors.left: cond ? parent.left : undefined` ternary -- the plain
    // ternary form left a stale anchor active after a round-trip toggle
    // (dock left -> right -> left), so both anchors.left AND anchors.right
    // ended up bound simultaneously. QtQuick derives width from the span
    // between two active anchors, silently overriding the explicit
    // `width: root.implicitWidth` below and blowing the bar up into a
    // huge pill spanning most of the window. AnchorChanges is the
    // Qt-documented way to reassign anchor lines reactively without this
    // failure mode -- it cleanly reverts the previous state's anchors
    // instead of relying on a binding evaluating to `undefined`.
    // background/content below use plain x/y/width/height bindings rather
    // than anchors -- both axes are always explicit (never just "let the
    // implicit size flow through"), which matters most for `content`:
    // Loader forces its loaded item to match ITS OWN size whenever that
    // size is unambiguous, but a single anchor line (position only, no
    // opposing pair) turned out NOT to reliably count as "explicit" for
    // that purpose, leaving Bar.qml sized down to a couple of px instead
    // of its real content. Plain width/height bindings have no such
    // ambiguity.
    StyledRect {
        id: background

        width: Settings.barHorizontal ? root.width : root.implicitWidth
        height: Settings.barHorizontal ? root.implicitWidth : root.height
        x: !Settings.barHorizontal && Settings.barPositionRight ? root.width - width : 0
        y: Settings.barHorizontal && Settings.barPositionBottom ? root.height - height : 0

        // Only the "full" style's own pill/square backdrop -- taskbar and
        // minimal draw their own full-bleed background internally
        // (TaskbarBar.qml/MinimalBar.qml), matching their own described
        // look instead of inheriting Full's rounded-strip treatment.
        radius: Settings.barSkin === "square" ? Tokens.rounding.small : Tokens.rounding.full
        color: Colours.tPalette.m3surfaceContainer
        border.width: 0
        border.color: Colours.palette.m3outlineVariant
        visible: root.shouldBeVisible && Settings.barStyle === "full"

        Behavior on radius {
            Anim { type: Anim.DefaultEffects }
        }

        DepthGradient {
            anchors.fill: parent
            radius: parent.radius
            baseColour: Colours.tPalette.m3surfaceContainer
        }
    }

    Loader {
        id: content

        width: Settings.barHorizontal ? root.width : root.contentWidth
        height: Settings.barHorizontal ? root.contentWidth : root.height
        x: !Settings.barHorizontal && Settings.barPositionRight ? root.width - width : 0
        y: Settings.barHorizontal && Settings.barPositionBottom ? root.height - height : 0

        active: root.shouldBeVisible

        sourceComponent: BarShell {
            thickness: root.contentWidth
            screen: root.screen
            screenState: root.screenState
            popouts: root.popouts // qmllint disable incompatible-type
            fullscreen: root.fullscreen
        }
    }

    // Passive hover tracking -- HoverHandler observes without grabbing the
    // mouse, so clicks still reach Bar.qml's own StateLayers/MouseAreas
    // underneath. Drives both the popout-on-hover system (checkPopout) and
    // the auto-show-on-hover bar state (isHovered) referenced by
    // shouldBeVisible above.
    //
    // REVERTED a same-day attempt to replace this with a plain MouseArea
    // (matching caelestia-dots/shell's own Interactions.qml, which uses
    // one). That swap broke something worse than it fixed: a MouseArea
    // with hoverEnabled: true is NOT passive the way HoverHandler is --
    // Qt Quick's traditional MouseArea event model consumes hover-move
    // events for the topmost MouseArea covering a point and does not
    // deliver them onward to overlapping/underlying MouseAreas the way
    // HoverHandler (a newer, explicitly non-exclusive Pointer Handler)
    // does. This top-level bar-covering MouseArea silently ate every
    // hover event before Workspaces.qml's own workspace-hover MouseArea,
    // StatusIcons.qml's pill MouseArea, and every status-icon component's
    // own click/hover MouseArea underneath ever saw them -- reported live
    // as "the highlight doesn't show up when hovering, the workspace
    // toggle shows no highlight, everything that used to show active
    // hover selection is gone." That regression was worse than the
    // original popout-miss bug this was trying to fix, so it's reverted
    // back to HoverHandler here. The real fix for missed
    // HoverHandler samples (StatusIcons.qml's own per-pill handler, and
    // Bar.qml's checkPopout logic) stays in place -- only the outer,
    // whole-bar-covering layer needed to stay a HoverHandler specifically
    // because it sits above every other interactive child in this file.
    HoverHandler {
        id: hoverHandler

        target: content
        onPointChanged: {
            if (Settings.barHorizontal) {
                if (point.position.x >= 0 && point.position.x <= content.width)
                    root.checkPopout(point.position.x);
            } else if (point.position.y >= 0 && point.position.y <= content.height) {
                root.checkPopout(point.position.y);
            }
        }
        onHoveredChanged: {
            root.isHovered = hovered;
            // Deferred via Qt.callLater, not checked synchronously here --
            // this component (BarWrapper.qml) and the flyout's own hover
            // guard (popouts/Wrapper.qml's flyoutHover) live in two
            // separate component trees, both independently reacting to
            // the SAME physical pointer-motion event when the cursor
            // crosses from the bar strip directly into the flush-adjacent
            // flyout (zero gap between them, see popouts/Wrapper.qml).
            // Qt Quick delivers each item's own hover-exit/hover-enter as
            // a separate signal for that one motion sample, with no
            // guarantee this handler's exit and the flyout's own enter
            // land in a particular order within the same tick. Checking
            // hoveringFlyout synchronously here could read its
            // NOT-YET-UPDATED value if this handler happens to run first,
            // closing a popout the cursor never actually left -- reported
            // live as "the second the mouse hovers over the margin gap
            // between the bar and the popout, it snaps away," reproducing
            // on every single crossing regardless of bar orientation,
            // which is exactly the signature of a same-tick ordering race
            // rather than a geometry gap (the geometry itself has zero
            // gap already). Qt.callLater defers this check to the next
            // event-loop iteration, by which point BOTH handlers'
            // synchronous work for this motion sample has already run,
            // so hoveringFlyout reflects its real, settled value.
            if (!hovered)
                Qt.callLater(() => {
                    if (!hoverHandler.hovered && !root.popouts.hoveringFlyout)
                        root.popouts.hasCurrent = false;
                });
        }
    }

    WheelHandler {
        target: content
        onWheel: event => root.handleWheel(Settings.barHorizontal ? point.position.x : point.position.y, Qt.point(event.angleDelta.x, event.angleDelta.y))
    }
}
