import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState

    implicitWidth: Settings.barVertical ? icon.implicitHeight : icon.implicitHeight + Tokens.padding.small
    implicitHeight: Settings.barVertical ? icon.implicitHeight + Tokens.padding.small : icon.implicitHeight

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
