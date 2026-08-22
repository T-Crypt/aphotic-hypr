import QtQuick
import qs.config
import qs.components
import qs.services

StyledRect {
    id: root

    color: Colours.palette.m3surfaceContainerHigh
    radius: Tokens.rounding.full

    implicitWidth: Settings.barVertical ? icon.implicitHeight + Tokens.padding.small * 2 : Settings.barInnerWidth
    implicitHeight: Settings.barVertical ? Settings.barInnerWidth : icon.implicitHeight + Tokens.padding.small * 2

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: "tune"
        color: Colours.palette.m3onSurfaceVariant
    }
}
