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

    readonly property bool isActive: modelData.theme === Themes.activeTheme && modelData.file === Themes.activeWallpaper

    width: ListView.view?.width ?? 0
    implicitHeight: Tokens.sizes.launcher.itemHeight

    function execute(): void {
        Themes.setTheme(modelData.theme, modelData.file);
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

        StyledRect {
            id: thumb

            anchors.verticalCenter: parent.verticalCenter
            width: parent.height * 0.7
            height: width
            radius: Tokens.rounding.medium
            color: Colours.palette.m3surfaceContainerHigh
            clip: true

            Image {
                anchors.fill: parent
                source: `file://${Config.launcher.wallpaperDir}/${root.modelData.theme}/${root.modelData.file}`
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }
        }

        Row {
            anchors.verticalCenter: thumb.verticalCenter
            width: parent.width - thumb.width - parent.spacing
            spacing: Tokens.spacing.small

            StyledText {
                text: root.modelData.file
                font: Tokens.font.body.medium
                elide: Text.ElideRight
                width: parent.width - (icon.visible ? icon.width + parent.spacing : 0)
            }

            MaterialIcon {
                id: icon
                visible: root.isActive
                anchors.verticalCenter: parent.verticalCenter
                text: "check_circle"
                fill: 1
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3primary
            }
        }
    }
}
