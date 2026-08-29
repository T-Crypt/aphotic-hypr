pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property var modelData
    required property ScreenState screenState

    width: ListView.view?.width ?? 0
    implicitHeight: Tokens.sizes.launcher.itemHeight

    // Hands the category id off via ScreenState (same one-shot pattern
    // as Launcher.qml's own launcherPrefill) rather than an IPC call --
    // SettingsWindow.qml consumes it the moment it becomes visible.
    function execute(): void {
        root.screenState.settingsCategory = root.modelData.id;
        root.screenState.settings = true;
    }

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: {
            root.execute();
            root.screenState.launcher = false;
        }
    }

    Row {
        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        MaterialIcon {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            text: root.modelData.icon
            fontStyle: Tokens.font.icon.large
            color: Colours.palette.m3onSurfaceVariant
        }

        Column {
            anchors.verticalCenter: icon.verticalCenter
            width: parent.width - icon.width - parent.spacing

            StyledText {
                text: root.modelData.label
                font: Tokens.font.body.medium
                elide: Text.ElideRight
                width: parent.width
            }

            StyledText {
                text: root.modelData.description
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
                width: parent.width
            }
        }
    }
}
