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

    // Same dark neutral surface every other bar style's background uses
    // (matches Taskbar's own m3surfaceContainer exactly) instead of a
    // full-bleed solid accent block -- a bold single-color fill read as
    // a genuine outlier against the rest of this repo's UI language,
    // where accent is reserved for active/interactive state (the active
    // workspace dot, a toggled indicator), never a whole background. The
    // thin accent border keeps a nod to "accent strip" without the
    // jarring full-color fill -- also a deliberate callback to the old
    // (pre-repurposing) "minimal" skin's own outline-only treatment.
    StyledRect {
        anchors.fill: parent
        color: Colours.tPalette.m3surfaceContainer
        radius: 0
        border.width: Config.border.thickness
        border.color: Colours.palette.m3primary
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
