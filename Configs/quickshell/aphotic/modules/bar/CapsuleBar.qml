pragma ComponentBehavior: Bound

import "capsule"
import "components"
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState

    readonly property bool horizontal: Settings.barHorizontal
    // Which way the popout grows: away from the screen edge the bar is
    // docked against, so it never covers the pill.
    readonly property bool growsAfter: root.horizontal ? !Settings.barPositionBottom : !Settings.barPositionRight

    // ---- Pill geometry --------------------------------------------------
    //
    // The pill NEVER resizes. Its length is a pure function of its own
    // content and a configured floor, so it is identical hovered and
    // unhovered, open and closed.
    //
    // That is the whole fix for the worst bug in the first pass: the pill
    // is centred along its length, so any change to that length slid every
    // control sideways out from under the pointer.
    readonly property int rowThickness: Settings.barInnerWidth + Tokens.padding.extraSmall * 2
    readonly property real rowExtent: root.horizontal ? collapsedRow.implicitWidth : collapsedRow.implicitHeight
    readonly property real alongExtent: Math.max(rowExtent + Tokens.padding.medium * 2, Config.bar.capsule.minLength)

    readonly property int popoutAlong: root.horizontal ? Config.bar.capsule.popoutWidth : Config.bar.capsule.stackedPopoutHeight
    readonly property int popoutAcross: root.horizontal ? Config.bar.capsule.popoutHeight : Config.bar.capsule.stackedPopoutWidth
    readonly property int popoutReach: Config.bar.capsule.gap + root.popoutAcross

    // ---- State ----------------------------------------------------------
    readonly property bool mediaAvailable: Settings.capsuleMedia && Players.active !== null
    property bool pinned: false
    property bool wsPeek: false

    // No dwell timer and no reveal delay anywhere on this path: hover is
    // the animation's start, not a countdown to it.
    readonly property bool hoverOpen: Settings.capsuleExpandOnHover && (chipHover.hovered || popoutHover.hovered)
    readonly property bool expanded: root.mediaAvailable && (root.pinned || root.hoverOpen)

    readonly property bool autohide: Settings.barVisibility === "autohide"
    readonly property bool shouldShow: !root.autohide || rootHover.hovered || root.wsPeek || root.expanded

    function handleWheel(pos: real, angleDelta: point): void {
        if (angleDelta.y > 0)
            Audio.incrementVolume();
        else if (angleDelta.y < 0)
            Audio.decrementVolume();
    }

    // Kept mounted through the collapse so the popout still reports a real
    // size while it springs shut -- same reasoning as the notch's
    // shownTileId (modules/notch/Notch.qml).
    property bool surfaceLatched: false

    onExpandedChanged: {
        if (root.expanded) {
            unlatch.stop();
            root.surfaceLatched = true;
        } else {
            unlatch.restart();
        }
    }

    onMediaAvailableChanged: {
        if (!root.mediaAvailable)
            root.pinned = false;
    }

    Timer {
        id: unlatch
        interval: 900
        onTriggered: root.surfaceLatched = false
    }

    Timer {
        id: wsPeekTimer
        interval: 1200
        onTriggered: root.wsPeek = false
    }

    // Tracks the popout's live extent, not its target, so the window's
    // input region follows the spring instead of snapping ahead of it.
    implicitWidth: root.horizontal ? root.alongExtent : root.rowThickness + popoutHost.width
    implicitHeight: root.horizontal ? root.rowThickness + popoutHost.height : root.alongExtent
    width: implicitWidth
    height: implicitHeight

    HoverHandler {
        id: rootHover
    }

    StyledRect {
        id: pill

        x: root.horizontal ? 0 : (root.growsAfter ? 0 : root.width - width)
        y: root.horizontal ? (root.growsAfter ? 0 : root.height - height) : 0
        width: root.horizontal ? root.alongExtent : root.rowThickness
        height: root.horizontal ? root.rowThickness : root.alongExtent

        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer

        transform: Translate {
            readonly property real hidden: root.rowThickness - Config.bar.capsule.peek

            x: !root.horizontal && !root.shouldShow ? (Settings.barPositionRight ? hidden : -hidden) : 0
            y: root.horizontal && !root.shouldShow ? (Settings.barPositionBottom ? hidden : -hidden) : 0

            Behavior on x {
                enabled: Settings.capsuleAnimations
                Anim {
                    type: Anim.Emphasized
                }
            }
            Behavior on y {
                enabled: Settings.capsuleAnimations
                Anim {
                    type: Anim.Emphasized
                }
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: 0.5
            shadowBlur: 0.5
            shadowVerticalOffset: 2
        }

        GridLayout {
            id: collapsedRow

            anchors.centerIn: parent
            flow: root.horizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
            rowSpacing: Tokens.spacing.small
            columnSpacing: Tokens.spacing.small

            CapsuleWorkspaces {
                Layout.alignment: Qt.AlignCenter
                screen: root.screen
                onSwitched: {
                    if (!root.autohide)
                        return;
                    root.wsPeek = true;
                    wsPeekTimer.restart();
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignCenter
                Layout.preferredWidth: root.horizontal ? 1 : 18
                Layout.preferredHeight: root.horizontal ? 18 : 1
                color: Colours.palette.m3outlineVariant
                opacity: 0.5
            }

            CapsuleClock {
                Layout.alignment: Qt.AlignCenter
                screenState: root.screenState
            }

            AgentIndicator {
                Layout.alignment: Qt.AlignCenter
                screenState: root.screenState
                showBackground: false
            }

            StatusIcons {
                Layout.alignment: Qt.AlignCenter
                screenState: root.screenState
            }

            CapsuleMediaChip {
                id: chip

                Layout.alignment: Qt.AlignCenter
                visible: root.mediaAvailable
                active: root.expanded
                onToggled: root.pinned = !root.pinned

                HoverHandler {
                    id: chipHover
                }
            }
        }
    }

    Item {
        id: popoutHost

        // Flush against the pill: the gap is transparent padding INSIDE
        // these bounds, never a hole between two items. A real gap is a
        // dead zone the pointer crosses with no hover events at all, which
        // closes the popout on the way to it.
        // Flush with the pill's trailing edge, which is where the chip
        // that opens it lives. Derived from the pill's own extent rather
        // than from the chip's laid-out position: a Layout child's x is
        // only valid after a polish pass, so reading it back would make
        // the popout's position depend on when the binding happened to
        // run. This lands in the same place with none of that.
        readonly property real along: Math.max(0, root.alongExtent - root.popoutAlong)

        clip: true

        x: root.horizontal ? along : (root.growsAfter ? root.rowThickness : 0)
        y: root.horizontal ? (root.growsAfter ? root.rowThickness : 0) : along
        width: root.horizontal ? root.popoutAlong : (root.expanded ? root.popoutReach : 0)
        height: root.horizontal ? (root.expanded ? root.popoutReach : 0) : root.popoutAlong

        visible: root.surfaceLatched

        Behavior on width {
            enabled: Settings.capsuleAnimations
            SpringAnimation {
                spring: 4
                damping: 0.62
                mass: 0.9
                epsilon: 0.25
            }
        }
        Behavior on height {
            enabled: Settings.capsuleAnimations
            SpringAnimation {
                spring: 4
                damping: 0.62
                mass: 0.9
                epsilon: 0.25
            }
        }

        HoverHandler {
            id: popoutHover
        }

        StyledRect {
            id: popoutSurface

            // Pinned to the edge nearest the pill, so the reveal wipes out
            // from under the bar instead of sliding in from off-screen.
            x: root.horizontal ? 0 : (root.growsAfter ? Config.bar.capsule.gap : popoutHost.width - width - Config.bar.capsule.gap)
            y: root.horizontal ? (root.growsAfter ? Config.bar.capsule.gap : popoutHost.height - height - Config.bar.capsule.gap) : 0
            width: root.horizontal ? root.popoutAlong : root.popoutAcross
            height: root.horizontal ? root.popoutAcross : root.popoutAlong

            radius: Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surfaceContainer

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Colours.palette.m3shadow
                shadowOpacity: 0.5
                shadowBlur: 0.5
                shadowVerticalOffset: 2
            }

            Loader {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                active: root.surfaceLatched

                sourceComponent: CapsuleMediaSurface {
                    live: root.expanded
                    stacked: !root.horizontal
                }
            }
        }
    }
}
