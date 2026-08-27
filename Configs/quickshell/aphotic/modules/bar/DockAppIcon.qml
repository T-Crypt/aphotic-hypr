pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property var item

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: Tokens.sizes.bar.innerWidth

    StateLayer {
        anchors.fill: parent
        radius: Tokens.rounding.full
        onClicked: {
            if (root.item.windows.length > 0)
                WindowList.focus(root.item.windows[0].address);
            else
                root.item.entry?.execute();
        }
    }

    IconImage {
        anchors.centerIn: parent
        source: root.item.icon
        implicitSize: parent.width * 0.6
    }

    Rectangle {
        visible: root.item.running
        width: 5
        height: 5
        radius: 2.5
        color: Colours.palette.m3primary
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
    }
}
