import QtQuick
import Quickshell
import qs.config

Item {
    id: root

    implicitWidth: Math.round(Tokens.font.body.large.pointSize * 1.2)
    implicitHeight: Math.round(Tokens.font.body.large.pointSize * 1.2)

    Image {
        anchors.centerIn: parent
        width: Math.round(Tokens.font.body.large.pointSize * 1.8)
        height: Math.round(Tokens.font.body.large.pointSize * 1.8)

        source: Quickshell.shellPath("assets/noctis-logo.svg")
        sourceSize.width: 96
        sourceSize.height: 96
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
    }
}
