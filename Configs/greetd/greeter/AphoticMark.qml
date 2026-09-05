import QtQuick

// Trimmed copy of qs.components/AphoticMark.qml, wired to this tree's own
// Colours singleton instead of the live shell's.
Item {
    id: root

    property color frameColour: Colours.textColor
    property color accentColour: Colours.primary

    implicitWidth: 512
    implicitHeight: 512

    Image {
        anchors.fill: parent
        source: "data/aphotic-mark-frame.svg"
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
        source: "data/aphotic-mark-accent.svg"
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
