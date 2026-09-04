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
    readonly property int thickness: Math.round(Settings.barInnerWidth * 0.72)

    // Holds its space for as long as there is a player. It used to collapse
    // to zero width when unhovered, which resized the centre-anchored pill
    // around it and slid every other control sideways under the pointer.
    implicitWidth: content.implicitWidth + Tokens.padding.small * 2
    implicitHeight: root.thickness

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.full
        color: root.active ? Colours.palette.m3secondaryContainer : "transparent"

        StateLayer {
            radius: parent.radius
            onClicked: root.toggled()
        }
    }

    RowLayout {
        id: content

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        CapsuleArtwork {
            Layout.alignment: Qt.AlignVCenter
            artSize: root.thickness - Tokens.padding.small
            cornerRadius: Tokens.rounding.small
            source: root.player ? Players.getArtUrl(root.player) : ""
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: 132
            text: root.player?.trackTitle ?? ""
            color: Colours.palette.m3onSurface
            font: Tokens.font.label.medium
            elide: Text.ElideRight
        }

        MaterialIcon {
            Layout.alignment: Qt.AlignVCenter
            text: root.player?.isPlaying ? "graphic_eq" : "pause"
            color: Colours.palette.m3primaryOnSurface
            fontStyle: Tokens.font.icon.small
            fill: 1
        }
    }
}
