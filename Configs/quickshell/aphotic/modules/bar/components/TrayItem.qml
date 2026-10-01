pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import Quickshell.Services.SystemTray
import qs.config
import qs.components.effects
import qs.services
import qs.utils

MouseArea {
    id: root

    property QtObject _sonarTarget: Loader {
        active: Settings.sonarEnabled
        sourceComponent: EchoTarget {
            target: root
            targetId: "core:tray/" + root.modelData.id
            label: root.modelData.title || root.modelData.id
            action: ""
            bindDescription: ""
            plugin: ""
            eligible: true
        }
    }

    required property SystemTrayItem modelData

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    implicitWidth: Tokens.font.body.small.pointSize * 2
    implicitHeight: Tokens.font.body.small.pointSize * 2

    onClicked: event => {
        if (event.button === Qt.LeftButton)
            modelData.activate();
        else
            modelData.secondaryActivate();
    }

    ColouredIcon {
        id: icon

        anchors.fill: parent
        source: Icons.getTrayIcon(root.modelData.id, root.modelData.icon)
        colour: Colours.palette.m3secondary
        layer.enabled: Config.bar.tray.recolour
    }
}
