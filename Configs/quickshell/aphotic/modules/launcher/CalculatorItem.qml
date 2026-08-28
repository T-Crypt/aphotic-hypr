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

    // toFixed(10) then back through Number() to round away float noise
    // (0.1+0.2 -> 0.30000000000000004) while still stripping trailing
    // zeros for a clean display -- toFixed alone would keep them.
    readonly property string formattedResult: Number(root.modelData.value.toFixed(10)).toString()

    function execute(): void {
        Quickshell.execDetached(["wl-copy", root.formattedResult]);
        Toaster.toast(qsTr("Copied"), root.formattedResult, "content_copy");
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
            text: "calculate"
            fontStyle: Tokens.font.icon.large
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            id: expression

            anchors.verticalCenter: icon.verticalCenter
            width: parent.width - icon.width - resultText.width - parent.spacing * 2
            text: root.modelData.expression
            font: Tokens.font.body.medium
            color: Colours.palette.m3onSurfaceVariant
            elide: Text.ElideRight
        }

        StyledText {
            id: resultText

            anchors.verticalCenter: icon.verticalCenter
            text: `= ${root.formattedResult}`
            font: Tokens.font.mono.medium
        }
    }
}
