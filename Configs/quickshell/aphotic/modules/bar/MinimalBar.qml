pragma ComponentBehavior: Bound

import "components"
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.modules.bar.popouts as BarPopouts
import "../../services/BarLayout.js" as BarLayout

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    required property real thickness

    implicitWidth: Settings.barHorizontal ? thickness : layout.implicitWidth + Tokens.padding.small * 2
    implicitHeight: Settings.barHorizontal ? layout.implicitHeight + Tokens.padding.small * 2 : thickness

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

    // Translucent Signal surface, no border: at rest the bar IS its
    // inner-edge line, so the idle hairline below carries the whole
    // outline instead of a filled accent strip.
    SignalSurface {
        anchors.fill: parent
        tone: Qt.alpha(Colours.signalStyle.bar, 0.6)
        radius: BarLayout.cornerRadius(Settings.barCorners, root.thickness)
        border.width: 0
    }

    SignalLine {
        horizontal: Settings.barHorizontal
        edge: (Settings.barHorizontal ? Settings.barPositionBottom : Settings.barPositionRight) ? "start" : "end"
        level: "idle"
    }

    RowLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        spacing: Tokens.spacing.medium
        layoutDirection: Qt.LeftToRight

        DockWorkspaces {
            screen: root.screen
        }

        MinimalIndicators {}

        Item {
            Layout.fillWidth: true
        }

        AgentIndicator {
            screenState: root.screenState
            showBackground: false
        }

        MinimalTray {
            id: tray
        }

        StyledText {
            text: Settings.twelveHourClock ? `${Time.hourStr}:${Time.minuteStr} ${Time.amPmStr.toLowerCase()}` : `${Time.hourStr}:${Time.minuteStr}`
            color: Colours.palette.m3secondaryOnSurface
            font: Tokens.font.body.small
        }
    }
}
