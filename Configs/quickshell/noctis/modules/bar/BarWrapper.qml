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

    readonly property int clampedWidth: Math.max(Config.border.minThickness, implicitWidth)
    readonly property int padding: Math.max(Tokens.padding.small, Config.border.thickness)
    readonly property int contentWidth: Settings.barInnerWidth + padding * 2
    readonly property int exclusiveZone: !disabled && (Settings.barPersistent || screenState.bar) ? contentWidth : Config.border.thickness
    readonly property bool shouldBeVisible: !fullscreen && !disabled && (Settings.barPersistent || screenState.bar || isHovered)
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
    visible: width > Config.border.thickness
    implicitWidth: fullscreen ? 0 : Config.border.thickness

    states: State {
        name: "visible"
        when: root.shouldBeVisible

        PropertyChanges {
            root.implicitWidth: root.contentWidth
        }
    }

    transitions: [
        Transition {
            from: ""
            to: "visible"

            Anim {
                target: root
                property: "implicitWidth"
            }
        },
        Transition {
            from: "visible"
            to: ""

            Anim {
                target: root
                property: "implicitWidth"
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
    StyledRect {
        id: background

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: !Settings.barPositionRight ? parent.right : undefined
        anchors.left: Settings.barPositionRight ? parent.left : undefined
        width: root.implicitWidth

        radius: Tokens.rounding.full
        color: Colours.tPalette.m3surfaceContainer
        visible: root.shouldBeVisible
    }

    Loader {
        id: content

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: !Settings.barPositionRight ? parent.right : undefined
        anchors.left: Settings.barPositionRight ? parent.left : undefined

        active: root.shouldBeVisible

        sourceComponent: Bar {
            width: root.contentWidth
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
            if (point.position.y >= 0 && point.position.y <= content.height)
                root.checkPopout(point.position.y);
        }
        onHoveredChanged: {
            root.isHovered = hovered;
            if (!hovered && !root.popouts.hoveringFlyout)
                root.popouts.hasCurrent = false;
        }
    }

    WheelHandler {
        target: content
        onWheel: event => root.handleWheel(point.position.y, Qt.point(event.angleDelta.x, event.angleDelta.y))
    }
}
