import QtQuick
import qs.config
import qs.components
import qs.components.effects
import qs.services

Item {
    id: root

    required property ScreenState screenState
    property color colour: Colours.palette.m3secondaryOnSurface
    // Full/Taskbar want the same background-chip treatment every other
    // entry (Clock/Tray/OsIcon/...) already has, so the agent icon has
    // its own visual boundary instead of blending into whatever's next
    // to it. Minimal is icon-only with no chips anywhere, so it opts out.
    property bool showBackground: true

    readonly property var provider: AgentProviders.providers[AgentProviders.selectedIndex] ?? AgentProviders.providers[0]
    readonly property var stat: AgentProviders.stats[AgentProviders.selectedIndex] ?? AgentProviders.stats[0]
    readonly property int badgeCount: root.provider.id === "ollama" ? root.stat.loadedModels.length : root.stat.sessionCount

    implicitWidth: root.showBackground ? Settings.barInnerWidth : icon.implicitWidth
    implicitHeight: root.showBackground ? Settings.barInnerWidth : icon.implicitHeight

    BioluminescentGlow {
        target: background
        intensity: root.badgeCount > 0 ? DepthFx.glowIntensity : 0
    }

    StyledRect {
        id: background

        visible: root.showBackground
        anchors.fill: parent
        radius: Tokens.rounding.full
        color: Colours.palette.m3surfaceContainerHigh
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        animate: true
        text: root.provider.icon
        color: root.colour
        fill: root.badgeCount > 0 ? 1 : 0
    }

    StyledRect {
        visible: root.badgeCount > 1

        anchors.top: icon.top
        anchors.right: icon.right
        anchors.topMargin: -Tokens.spacing.extraSmall / 2
        anchors.rightMargin: -Tokens.spacing.extraSmall / 2

        implicitWidth: Math.max(count.implicitWidth + Tokens.padding.extraSmall, Tokens.spacing.medium)
        implicitHeight: Tokens.spacing.medium
        radius: Tokens.rounding.full
        color: Colours.palette.m3primary

        StyledText {
            id: count

            anchors.centerIn: parent
            text: root.badgeCount > 9 ? "9+" : String(root.badgeCount)
            font: Tokens.font.label.small
            color: Colours.palette.m3onPrimary
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -Tokens.padding.small
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                root.screenState.agentPanel = !root.screenState.agentPanel;
            else if (mouse.button === Qt.RightButton)
                AgentProviders.launchSelected();
            else if (mouse.button === Qt.MiddleButton)
                AgentProviders.cycle();
        }
    }
}
