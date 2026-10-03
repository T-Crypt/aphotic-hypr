import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: root

    property QtObject _sonarTarget: Loader {
        active: Settings.sonarEnabled
        sourceComponent: EchoTarget {
            target: root
            targetId: "core:bar/power"
            label: qsTr("Power menu")
            action: "session"
            bindDescription: "Toggle session menu"
            plugin: ""
            eligible: true
        }
    }

    required property ScreenState screenState

    implicitWidth: Settings.barHorizontal ? icon.implicitHeight : icon.implicitHeight + Tokens.padding.small
    implicitHeight: Settings.barHorizontal ? icon.implicitHeight + Tokens.padding.small : icon.implicitHeight

    StateLayer {
        // Cursed workaround to make the height larger than the parent
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: icon.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.full
        onClicked: root.screenState.session = !root.screenState.session
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent

        text: "power_settings_new"
        color: Colours.palette.m3error
        fontStyle: Tokens.font.icon.builders.small.weight(Font.Bold).build()
    }
}
