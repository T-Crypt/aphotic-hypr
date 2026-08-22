pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property HyprlandToplevel modelData
    required property ScreenState screenState

    width: ListView.view?.width ?? 0
    implicitHeight: Tokens.sizes.launcher.itemHeight

    function execute(): void {
        const address = root.modelData.address;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ address = "${address}" })` : `focuswindow address:${address}`);
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

        IconImage {
            id: icon

            asynchronous: true
            source: Quickshell.iconPath(root.modelData.lastIpcObject?.class, "application-x-executable")
            implicitSize: parent.height * 0.7
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: icon.verticalCenter
            width: parent.width - icon.width - parent.spacing

            StyledText {
                text: root.modelData.title || root.modelData.lastIpcObject?.class || qsTr("Unknown window")
                font: Tokens.font.body.medium
                elide: Text.ElideRight
                width: parent.width
            }

            StyledText {
                text: root.modelData.workspace?.name ?? ""
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
                width: parent.width
            }
        }
    }
}
