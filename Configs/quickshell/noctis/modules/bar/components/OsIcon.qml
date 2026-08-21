import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

StyledRect {
    id: root

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: Tokens.sizes.bar.innerWidth

    color: Colours.palette.m3surfaceContainerHigh
    radius: Tokens.rounding.full

    Image {
        anchors.centerIn: parent
        width: parent.implicitWidth - Tokens.padding.small * 2
        height: width

        source: Quickshell.shellPath("assets/noctis-logo.svg")
        sourceSize.width: 96
        sourceSize.height: 96
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
    }
}
