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

    function execute(): void {
        Quickshell.execDetached(["kitty", "--directory", root.modelData.path, "zsh", "-ic", "claude"]);
        Quickshell.execDetached(["code", root.modelData.path]);
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
            text: root.modelData.icon === "code" ? "code" : "folder"
            fontStyle: Tokens.font.icon.large
            color: Colours.palette.m3onSurfaceVariant
        }

        Column {
            anchors.verticalCenter: icon.verticalCenter
            width: parent.width - icon.width - parent.spacing

            StyledText {
                text: root.modelData.name
                font: Tokens.font.body.medium
                elide: Text.ElideRight
                width: parent.width
            }

            StyledText {
                text: root.modelData.path
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
                width: parent.width
            }
        }
    }
}
