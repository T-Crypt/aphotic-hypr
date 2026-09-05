pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property DesktopEntry modelData
    required property ScreenState screenState

    width: ListView.view?.width ?? 0
    implicitHeight: Tokens.sizes.launcher.itemHeight

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: {
            LauncherUsage.recordLaunch(root.modelData.id);
            root.modelData.execute();
            root.screenState.launcher = false;
        }
    }

    Row {
        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        AppIcon {
            id: icon

            asynchronous: true
            name: root.modelData.icon
            appClass: [root.modelData.id, root.modelData.name]
            size: parent.height * 0.7
            fontStyle: Tokens.font.icon.large
            anchors.verticalCenter: parent.verticalCenter
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
                text: root.modelData.comment || root.modelData.genericName || ""
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
                width: parent.width
            }
        }
    }
}
