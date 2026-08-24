import QtQuick
import qs.components.effects
import qs.services

Item {
    id: root

    property color frameColour: Colours.palette.m3onSurface
    property color accentColour: Colours.palette.m3primary

    implicitWidth: 512
    implicitHeight: 512

    Image {
        anchors.fill: parent
        source: "../data/aphotic-mark-frame.svg"
        fillMode: Image.PreserveAspectFit
        sourceSize.width: root.width
        sourceSize.height: root.height
        smooth: true

        layer.enabled: true
        layer.effect: Colouriser {
            colorizationColor: root.frameColour
        }
    }

    Image {
        anchors.fill: parent
        source: "../data/aphotic-mark-accent.svg"
        fillMode: Image.PreserveAspectFit
        sourceSize.width: root.width
        sourceSize.height: root.height
        smooth: true

        layer.enabled: true
        layer.effect: Colouriser {
            colorizationColor: root.accentColour
        }
    }
}
