import QtQuick
import qs.config
import qs.components
import qs.services

StyledRect {
    id: root

    property QtObject _sonarTarget: Loader {
        active: Settings.sonarEnabled
        sourceComponent: EchoTarget {
            target: root
            targetId: "core:bar/settingsbutton"
            label: qsTr("Settings")
            action: "settings"
            bindDescription: "Toggle Settings"
            plugin: ""
            eligible: true
        }
    }

    color: Settings.barSignal ? "transparent" : Colours.palette.m3surfaceContainerHigh
    radius: Tokens.rounding.full

    implicitWidth: Settings.barHorizontal ? icon.implicitHeight + Tokens.padding.small * 2 : Settings.barInnerWidth
    implicitHeight: Settings.barHorizontal ? Settings.barInnerWidth : icon.implicitHeight + Tokens.padding.small * 2

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: "tune"
        color: Colours.palette.m3onSurfaceVariant
    }
}
