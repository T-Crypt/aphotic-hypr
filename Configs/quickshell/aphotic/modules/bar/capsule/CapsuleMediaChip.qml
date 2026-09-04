pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    property bool shown: false
    property bool active: false
    signal toggled

    readonly property var player: Players.active
    readonly property int thickness: Math.round(Settings.barInnerWidth * 0.72)

    // Steps straight to its full size rather than animating: the capsule
    // around it owns the one width animation for the whole reveal, and a
    // second easing curve here would fight it.
    implicitWidth: root.shown ? content.implicitWidth + Tokens.padding.small * 2 : 0
    implicitHeight: root.thickness

    opacity: root.shown ? 1 : 0
    visible: opacity > 0
    // Width drops to zero the instant `shown` goes false while the fade
    // is still running, so the centred content would spill out of the row
    // for the length of the fade.
    clip: true

    Behavior on opacity {
        enabled: Settings.capsuleAnimations
        Anim { type: Anim.DefaultEffects }
    }

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
