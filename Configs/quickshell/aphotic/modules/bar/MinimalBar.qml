pragma ComponentBehavior: Bound

import "components"
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    required property real thickness

    readonly property color accent: Colours.palette.m3primary
    readonly property color onAccent: Colours.contrastOn(accent)

    implicitWidth: Settings.barVertical ? thickness : layout.implicitWidth + Tokens.padding.small * 2
    implicitHeight: Settings.barVertical ? layout.implicitHeight + Tokens.padding.small * 2 : thickness

    function closeTray(): void {
        tray.expanded = false;
    }

    function checkPopout(pos: real): void {}

    function handleWheel(pos: real, angleDelta: point): void {
        if (angleDelta.y > 0)
            Audio.incrementVolume();
        else if (angleDelta.y < 0)
            Audio.decrementVolume();
    }

    StyledRect {
        anchors.fill: parent
        color: root.accent
        radius: 0
    }

    RowLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        spacing: Tokens.spacing.medium
        layoutDirection: Qt.LeftToRight

        DockWorkspaces {
            screen: root.screen
            activeColour: root.onAccent
            occupiedColour: Qt.alpha(root.onAccent, 0.7)
            emptyColour: Qt.alpha(root.onAccent, 0.35)
        }

        MinimalIndicators {
            colour: root.onAccent
        }

        Item {
            Layout.fillWidth: true
        }

        MinimalTray {
            id: tray
        }

        StyledText {
            text: Settings.twelveHourClock ? `${Time.hourStr}:${Time.minuteStr} ${Time.amPmStr.toLowerCase()}` : `${Time.hourStr}:${Time.minuteStr}`
            color: root.onAccent
            font: Tokens.font.body.small
        }
    }
}
