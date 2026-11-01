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

    implicitWidth: Settings.barHorizontal ? layout.implicitWidth + Tokens.padding.small * 2 : thickness
    implicitHeight: Settings.barHorizontal ? thickness : layout.implicitHeight + Tokens.padding.small * 2

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

    // One column when docked to a side: a row would run past the strip's
    // width and the wrapper clips whatever overflows.
    GridLayout {
        id: layout

        readonly property int crossAlign: Settings.barHorizontal ? Qt.AlignVCenter : Qt.AlignHCenter

        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        flow: Settings.barHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
        rowSpacing: Tokens.spacing.medium
        columnSpacing: Tokens.spacing.medium
        layoutDirection: Qt.LeftToRight

        DockWorkspaces {
            Layout.alignment: layout.crossAlign
            screen: root.screen
        }

        MinimalIndicators {
            Layout.alignment: layout.crossAlign
        }

        Item {
            Layout.fillWidth: Settings.barHorizontal
            Layout.fillHeight: !Settings.barHorizontal
        }

        AgentIndicator {
            Layout.alignment: layout.crossAlign
            screenState: root.screenState
            showBackground: false
        }

        MinimalTray {
            id: tray

            Layout.alignment: layout.crossAlign
        }

        StyledText {
            Layout.alignment: layout.crossAlign
            horizontalAlignment: Text.AlignHCenter
            text: {
                const sep = Settings.barHorizontal ? ":" : "\n";
                const clock = `${Time.hourStr}${sep}${Time.minuteStr}`;
                return Settings.twelveHourClock && Settings.barHorizontal ? `${clock} ${Time.amPmStr.toLowerCase()}` : clock;
            }
            color: Colours.signalSecondaryOnSurface
            font: Tokens.font.body.small
        }
    }
}
