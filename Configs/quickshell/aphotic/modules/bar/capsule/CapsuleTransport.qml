pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

RowLayout {
    id: root

    readonly property var player: Players.active
    property int segmentHeight: 34

    spacing: 3

    component Segment: StyledRect {
        id: seg

        required property string glyph
        required property bool available
        property bool accent: false
        property int outerRadius: Tokens.rounding.small
        signal activated

        Layout.preferredHeight: root.segmentHeight
        Layout.alignment: Qt.AlignVCenter

        color: seg.accent ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh
        opacity: seg.available ? 1 : 0.38
        scale: state_.pressed ? 0.94 : (state_.containsMouse && seg.available ? 1.05 : 1)

        Behavior on scale {
            enabled: Settings.capsuleAnimations
            Anim { type: Anim.FastSpatial }
        }

        StateLayer {
            id: state_

            radius: seg.radius
            disabled: !seg.available
            onClicked: seg.activated()
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: seg.glyph
            fill: 1
            color: seg.accent ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            fontStyle: seg.accent ? Tokens.font.icon.large : Tokens.font.icon.medium
        }
    }

    Segment {
        id: prevSeg

        Layout.preferredWidth: 46
        glyph: "skip_previous"
        available: root.player?.canGoPrevious ?? false
        topLeftRadius: root.segmentHeight / 2
        bottomLeftRadius: root.segmentHeight / 2
        topRightRadius: prevSeg.outerRadius
        bottomRightRadius: prevSeg.outerRadius
        onActivated: root.player?.previous()
    }

    Segment {
        id: playSeg

        Layout.preferredWidth: 62
        glyph: root.player?.isPlaying ? "pause" : "play_arrow"
        available: root.player?.canTogglePlaying ?? false
        accent: true
        radius: playSeg.outerRadius
        onActivated: root.player?.togglePlaying()
    }

    Segment {
        id: nextSeg

        Layout.preferredWidth: 46
        glyph: "skip_next"
        available: root.player?.canGoNext ?? false
        topRightRadius: root.segmentHeight / 2
        bottomRightRadius: root.segmentHeight / 2
        topLeftRadius: nextSeg.outerRadius
        bottomLeftRadius: nextSeg.outerRadius
        onActivated: root.player?.next()
    }
}
