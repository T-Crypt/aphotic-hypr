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
    readonly property int thickness: Settings.barInnerWidth + Tokens.padding.extraSmall * 2

    readonly property bool mediaAvailable: Settings.capsuleMedia && Players.active !== null
    property bool pinned: false
    property bool hoverExpand: false
    property bool trackPeek: false
    property bool wsPeek: false

    readonly property bool expanded: root.mediaAvailable && (root.pinned || root.hoverExpand)
    readonly property bool peeking: root.mediaAvailable && (capsuleHover.hovered || root.trackPeek || root.expanded)

    readonly property bool autohide: Settings.barVisibility === "autohide"
    readonly property bool shouldShow: !root.autohide || revealHover.hovered || root.wsPeek || root.trackPeek || root.expanded

    // "Along" is the bar's length (screen width when docked top/bottom,
    // screen height when docked left/right); "across" is its thickness.
    readonly property int expandedAlong: root.horizontal ? Config.bar.capsule.expandedWidth : Config.bar.capsule.stackedHeight
    readonly property int expandedAcross: root.horizontal ? Config.bar.capsule.expandedHeight : Config.bar.capsule.stackedWidth

    // Floored at the collapsed footprint. A user carrying a lot of status
    // icons can already be wider than the configured expanded shape, and
    // without the floor the capsule visibly narrows as it opens.
    readonly property real targetWidth: root.expanded ? Math.max(root.horizontal ? root.expandedAlong : root.expandedAcross, hoverTarget.width) : hoverTarget.width
    readonly property real targetHeight: root.expanded ? Math.max(root.horizontal ? root.expandedAcross : root.expandedAlong, hoverTarget.height) : hoverTarget.height

    function handleWheel(pos: real, angleDelta: point): void {
        if (angleDelta.y > 0)
            Audio.incrementVolume();
        else if (angleDelta.y < 0)
            Audio.decrementVolume();
    }

    // Latched past the collapse so the surface still reports a real size
    // while the capsule shrinks under it -- same reasoning as the notch's
    // shownTileId (modules/notch/Notch.qml).
    property bool surfaceLatched: false
    property bool revealed: false

    readonly property string trackKey: Players.active ? `${Players.getIdentity(Players.active)} ${Players.active.trackTitle ?? ""}` : ""

    onExpandedChanged: {
        if (root.expanded) {
            unlatch.stop();
            root.surfaceLatched = true;
            revealTimer.restart();
        } else {
            revealTimer.stop();
            root.revealed = false;
            unlatch.restart();
        }
    }

    onTrackKeyChanged: {
        if (!root.mediaAvailable || root.trackKey.length === 0)
            return;
        root.trackPeek = true;
        trackPeekTimer.restart();
    }

    onMediaAvailableChanged: {
        if (root.mediaAvailable)
            return;
        root.pinned = false;
        root.hoverExpand = false;
        root.trackPeek = false;
    }

    onPeekingChanged: {
        if (!root.peeking)
            dwell.stop();
    }

    Timer {
        id: revealTimer
        interval: 150
        onTriggered: root.revealed = true
    }

    Timer {
        id: unlatch
        interval: Tokens.anim.durations.normal + 80
        onTriggered: root.surfaceLatched = false
    }

    Timer {
        id: trackPeekTimer
        interval: 4000
        onTriggered: root.trackPeek = false
    }

    Timer {
        id: wsPeekTimer
        interval: 1200
        onTriggered: root.wsPeek = false
    }

    Timer {
        id: dwell
        interval: 350
        onTriggered: root.hoverExpand = true
    }

    implicitWidth: capsule.width
    implicitHeight: capsule.height
    // Never shrinks below the collapsed footprint: this item's bounds are
    // the window's whole input region (see CapsuleWindow.qml's mask), so a
    // capsule translated away by auto-hide would otherwise take its own
    // hover-to-reveal target with it.
    width: Math.max(implicitWidth, hoverTarget.width)
    height: Math.max(implicitHeight, hoverTarget.height)

    Item {
        id: hoverTarget

        width: root.horizontal ? collapsedRow.implicitWidth + Tokens.padding.medium * 2 : root.thickness
        height: root.horizontal ? root.thickness : collapsedRow.implicitHeight + Tokens.padding.medium * 2
    }

    HoverHandler {
        id: revealHover
        target: hoverTarget
    }

    StyledRect {
        id: capsule

        anchors.centerIn: parent
        clip: true

        width: root.targetWidth
        height: root.targetHeight
        // Half the collapsed thickness rather than Tokens.rounding.full:
        // 999999 spends the whole animation above width/2 (where every
        // value renders identically) and then drops through the visible
        // range in the last few frames. Same trap the notch documents.
        radius: root.expanded ? Tokens.rounding.extraLarge : root.thickness / 2
        color: Colours.tPalette.m3surfaceContainer

        opacity: root.shouldShow ? 1 : 0

        transform: Translate {
            x: !root.horizontal && !root.shouldShow ? (Settings.barPositionRight ? capsule.width : -capsule.width) : 0
            y: root.horizontal && !root.shouldShow ? (Settings.barPositionBottom ? capsule.height : -capsule.height) : 0

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

        Behavior on width {
            enabled: Settings.capsuleAnimations
            Anim {
                type: Anim.Emphasized
            }
        }
        Behavior on height {
            enabled: Settings.capsuleAnimations
            Anim {
                type: Anim.Emphasized
            }
        }
        Behavior on radius {
            enabled: Settings.capsuleAnimations
            Anim {
                type: Anim.Emphasized
            }
        }
        Behavior on opacity {
            enabled: Settings.capsuleAnimations
            Anim {
                type: Anim.Emphasized
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

        HoverHandler {
            id: capsuleHover

            onHoveredChanged: {
                if (capsuleHover.hovered)
                    return;
                dwell.stop();
                root.hoverExpand = false;
            }
        }

        // Declared BEFORE the surface below, so every real control inside
        // it (transport buttons, the seek strip) sits on top and takes its
        // own clicks first -- this only ever catches a click on the
        // surface's empty space. Without it a pinned capsule has no way
        // back: expanding hides the chip that pinned it.
        MouseArea {
            anchors.fill: parent
            enabled: root.expanded
            onClicked: {
                root.pinned = false;
                root.hoverExpand = false;
            }
        }

        GridLayout {
            id: collapsedRow

            anchors.centerIn: parent
            flow: root.horizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
            rowSpacing: Tokens.spacing.small
            columnSpacing: Tokens.spacing.small

            opacity: root.expanded ? 0 : 1
            visible: opacity > 0

            Behavior on opacity {
                enabled: Settings.capsuleAnimations
                Anim {
                    type: Anim.FastEffects
                }
            }

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
                shown: root.peeking
                active: root.pinned
                onToggled: {
                    root.pinned = !root.pinned;
                    root.hoverExpand = false;
                    dwell.stop();
                }
            }
        }

        Loader {
            id: surface

            anchors.centerIn: parent
            active: root.surfaceLatched

            // Laid out at the TARGET size, never at the capsule's animating
            // one: the surface is built once at its final geometry and the
            // capsule's own clip reveals it, rather than the whole layout
            // re-solving on every frame of the expand.
            width: root.targetWidth - Tokens.padding.large * 2
            height: root.targetHeight - Tokens.padding.large * 2

            opacity: root.revealed ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                enabled: Settings.capsuleAnimations
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            sourceComponent: CapsuleMediaSurface {
                live: root.expanded
            }
        }
    }

    // Dwell-to-expand keys off the chip's own hover, but the collapse
    // keys off the whole capsule's -- expanding hides the chip, so keying
    // both on the chip would snap it straight back shut.
    HoverHandler {
        id: chipHover

        target: chip
        onHoveredChanged: {
            if (!Settings.capsuleExpandOnHover)
                return;
            if (chipHover.hovered && root.peeking && !root.expanded)
                dwell.restart();
            else
                dwell.stop();
        }
    }
}
