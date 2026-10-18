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

    readonly property string notchEdge: BarLayout.notchEdge(Settings.barHorizontal, Settings.barPositionBottom, Settings.barPositionRight)

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

    // No border and no extra tint: at rest the bar IS its inner-edge line,
    // and its fill matches the joined notch fill exactly so the join does
    // not step in tone.
    SignalSurface {
        anchors.fill: parent
        radius: BarLayout.cornerRadius(Settings.barCorners, root.thickness)
        border.width: 0
    }

    SignalLine {
        horizontal: Settings.barHorizontal
        edge: root.notchEdge
        gapLength: root.screenState.notchSpan
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
            color: Colours.signalSecondaryOnSurface
            font: Tokens.font.body.small
        }
    }
}
