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
        Wallpapers.setWallpaper(root.modelData.path);
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

        Image {
            id: thumb

            anchors.verticalCenter: parent.verticalCenter
            width: parent.height * 0.7
            height: width
            source: `file://${root.modelData.path}`
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true

            layer.enabled: true
            layer.smooth: true
        }

        StyledText {
            anchors.verticalCenter: thumb.verticalCenter
            text: root.modelData.name
            font: Tokens.font.body.medium
            elide: Text.ElideRight
            width: parent.width - thumb.width - parent.spacing
        }
    }
}
