import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState
    property color colour: Colours.palette.m3secondaryOnSurface

    readonly property var provider: AgentProviders.providers[AgentProviders.selectedIndex] ?? AgentProviders.providers[0]
    readonly property var stat: AgentProviders.stats[AgentProviders.selectedIndex] ?? AgentProviders.stats[0]
    readonly property int badgeCount: root.provider.id === "ollama" ? root.stat.loadedModels.length : root.stat.sessionCount

    implicitWidth: icon.implicitWidth
    implicitHeight: icon.implicitHeight

    MaterialIcon {
        id: icon

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
