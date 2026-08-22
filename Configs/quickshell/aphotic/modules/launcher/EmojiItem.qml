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
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", root.modelData.emoji]);
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

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.modelData.emoji
            font: Tokens.font.body.large
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.modelData.name
            font: Tokens.font.body.medium
            color: Colours.palette.m3onSurfaceVariant
            elide: Text.ElideRight
            width: parent.width - parent.spacing - Tokens.font.body.large.pointSize * 2
        }
    }
}
