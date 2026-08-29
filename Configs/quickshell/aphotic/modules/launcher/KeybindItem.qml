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

    // Keybinds aren't "launchable" the way an app/project/window is --
    // copying the combo to the clipboard is the useful action here, so
    // you can paste it wherever you actually needed to look it up for
    // (a README, a chat message, etc). Toaster confirms the copy landed,
    // since a silent clipboard write gives no feedback that anything
    // happened.
    function execute(): void {
        Quickshell.execDetached(["wl-copy", root.modelData.combo]);
        Toaster.toast(qsTr("Copied"), root.modelData.combo, "content_copy");
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
            text: "keyboard"
            fontStyle: Tokens.font.icon.large
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            id: description

            anchors.verticalCenter: icon.verticalCenter
            width: parent.width - icon.width - combo.width - parent.spacing * 2
            text: root.modelData.description
            font: Tokens.font.body.medium
            elide: Text.ElideRight
        }

        StyledRect {
            id: combo

            anchors.verticalCenter: icon.verticalCenter
            implicitWidth: comboText.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: comboText.implicitHeight + Tokens.padding.extraSmall * 2
            radius: Tokens.rounding.small
            color: Colours.palette.m3surfaceContainer

            StyledText {
                id: comboText

                anchors.centerIn: parent
                text: root.modelData.combo
                font: Tokens.font.mono.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
