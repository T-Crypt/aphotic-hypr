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
    readonly property bool hiddenMode: Settings.barVisibility === "hidden"
    // BarWindow.qml's input mask needs a wider hover target than root's
    // own (collapsed, in autohide mode) bounds -- content is already
    // always sized to the full contentWidth/height regardless of
    // collapse state (see below), it's just clipped visually by root's
    // own clip:true. Exposed so the window can mask to this instead of
    // root when it needs a real, hittable hover-to-reveal zone rather
    // than a literal couple-of-pixels sliver.
    readonly property alias hoverTarget: content

    readonly property int clampedWidth: Math.max(Config.border.minThickness, implicitWidth)
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
        (content.item as Bar)?.closeTray();
    }

    function checkPopout(y: real): void {
        (content.item as Bar)?.checkPopout(y);
    }

    function handleWheel(y: real, angleDelta: point): void {
        (content.item as Bar)?.handleWheel(y, angleDelta);
    }

    clip: true
    // Anchor pairs decide which axis is actually screen-edge-driven (see
    // BarWindow.qml's own dual implicitWidth/implicitHeight comment) -- the
    // other axis is this collapsible thickness, whichever one that is.
    visible: (Settings.barVertical ? height : width) > 0
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

        width: Settings.barVertical ? root.width : root.implicitWidth
        height: Settings.barVertical ? root.implicitWidth : root.height
        x: !Settings.barVertical && Settings.barPositionRight ? root.width - width : 0
        y: Settings.barVertical && Settings.barPositionBottom ? root.height - height : 0

        radius: Settings.barSkin === "square" ? Tokens.rounding.small : Tokens.rounding.full
        color: Settings.barSkin === "minimal" ? "transparent" : Colours.tPalette.m3surfaceContainer
        border.width: Settings.barSkin === "minimal" ? Config.border.thickness : 0
        border.color: Colours.palette.m3outlineVariant
        visible: root.shouldBeVisible

        Behavior on radius {
            Anim { type: Anim.DefaultEffects }
        }
    }

    Loader {
        id: content

        width: Settings.barVertical ? root.width : root.contentWidth
        height: Settings.barVertical ? root.contentWidth : root.height
        x: !Settings.barVertical && Settings.barPositionRight ? root.width - width : 0
        y: Settings.barVertical && Settings.barPositionBottom ? root.height - height : 0

        active: root.shouldBeVisible

        sourceComponent: Bar {
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
    // shouldBeVisible above -- neither was ever actually wired to real
    // mouse input before this, so popouts could only be triggered by
    // debug hacks and would never dismiss.
    HoverHandler {
        id: hoverHandler

        target: content
        onPointChanged: {
            if (Settings.barVertical) {
                if (point.position.x >= 0 && point.position.x <= content.width)
                    root.checkPopout(point.position.x);
            } else if (point.position.y >= 0 && point.position.y <= content.height) {
                root.checkPopout(point.position.y);
            }
        }
        onHoveredChanged: {
            root.isHovered = hovered;
            if (!hovered && !root.popouts.hoveringFlyout)
                root.popouts.hasCurrent = false;
        }
    }

    WheelHandler {
        target: content
        onWheel: event => root.handleWheel(Settings.barVertical ? point.position.x : point.position.y, Qt.point(event.angleDelta.x, event.angleDelta.y))
    }
}
