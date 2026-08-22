pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services

StyledRect {
    id: root

    readonly property color colour: Colours.palette.m3tertiaryOnSurface

    color: Colours.palette.m3surfaceContainerHigh
    radius: Tokens.rounding.full

    readonly property bool active: Players.active !== null

    clip: true
    implicitWidth: active ? (Settings.barVertical ? icon.implicitHeight + Tokens.padding.small * 2 : Settings.barInnerWidth) : 0
    implicitHeight: active ? (Settings.barVertical ? Settings.barInnerWidth : icon.implicitHeight + Tokens.padding.small * 2) : 0
    visible: implicitHeight > 0

    Behavior on implicitHeight {
        Anim {}
    }

    StateLayer {
        radius: root.radius
        disabled: !Players.active?.canTogglePlaying
        onClicked: Players.active?.togglePlaying()
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        animate: true
        text: Players.active?.isPlaying ? "pause" : "play_arrow"
        fill: 1
        color: root.colour
    }
}
