pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    property bool active: false
    signal toggled

    readonly property var player: Players.active
    readonly property int inner: Math.round(Settings.barInnerWidth * 0.72)

    // Holds its space for as long as there is a player. It used to collapse
    // to zero width when unhovered, which resized the centre-anchored pill
    // around it and slid every other control sideways under the pointer.
    //
    // Cross-axis size is pinned to the strip's own thickness in BOTH
    // orientations. This used to be a fixed horizontal row whatever the
    // bar's orientation, so a side-docked pill rendered a ~200px-wide chip
    // inside a ~48px-wide strip: the track title ran off the pill and off
    // the screen, and because the window masks to the bar's bounds, every
    // pixel of it outside those bounds was dead to hover and clicks.
    implicitWidth: Settings.barHorizontal ? content.implicitWidth + Tokens.padding.small * 2 : Settings.barInnerWidth
    implicitHeight: Settings.barHorizontal ? root.inner : content.implicitHeight + Tokens.padding.small * 2

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.full
        color: root.active ? Colours.palette.m3secondaryContainer : "transparent"

        StateLayer {
            radius: parent.radius
            onClicked: root.toggled()
        }
    }

    GridLayout {
        id: content

        anchors.centerIn: parent
        flow: Settings.barHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
        columnSpacing: Tokens.spacing.small
        rowSpacing: Tokens.spacing.extraSmall

        CapsuleArtwork {
            Layout.alignment: Qt.AlignCenter
            artSize: root.inner - Tokens.padding.small
            cornerRadius: Tokens.rounding.small
            source: root.player ? Players.getArtUrl(root.player) : ""
        }

        // There is no room for a title in a strip one icon wide, and the
        // artwork already says which track this is.
        StyledText {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: 132
            visible: Settings.barHorizontal
            text: root.player?.trackTitle ?? ""
            color: Colours.palette.m3onSurface
            font: Tokens.font.label.medium
            elide: Text.ElideRight
        }

        MaterialIcon {
            Layout.alignment: Qt.AlignCenter
            text: root.player?.isPlaying ? "graphic_eq" : "pause"
            color: Colours.palette.m3primaryOnSurface
            fontStyle: Tokens.font.icon.small
            fill: 1
        }
    }
}
