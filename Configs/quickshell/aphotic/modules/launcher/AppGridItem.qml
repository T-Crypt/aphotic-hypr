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

    width: GridView.view?.cellWidth ?? 0
    height: GridView.view?.cellHeight ?? 0

    function execute(): void {
        LauncherUsage.recordLaunch(root.modelData.id);
        root.modelData.execute();
        root.screenState.launcher = false;
    }

    StateLayer {
        anchors.fill: parent
        anchors.margins: Tokens.spacing.extraSmall
        radius: Tokens.rounding.large
        onClicked: root.execute()
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - Tokens.spacing.small * 2
        spacing: Tokens.spacing.small

        IconImage {
            anchors.horizontalCenter: parent.horizontalCenter
            asynchronous: true
            source: Quickshell.iconPath(root.modelData.icon, "image-missing")
            implicitSize: 48
        }

        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.modelData.name
            font: Tokens.font.body.small
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
