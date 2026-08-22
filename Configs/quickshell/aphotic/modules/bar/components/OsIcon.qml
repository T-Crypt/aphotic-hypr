import QtQuick
import qs.config
import qs.components
import qs.services

StyledRect {
    id: root

    implicitWidth: Settings.barInnerWidth
    implicitHeight: Settings.barInnerWidth

    color: Colours.palette.m3surfaceContainerHigh
    radius: Tokens.rounding.full

    AphoticMark {
        anchors.centerIn: parent
        width: root.implicitWidth - Tokens.padding.extraSmall * 2
        height: width
    }
}
