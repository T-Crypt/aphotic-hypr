import QtQuick
import Quickshell

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            anchors.top: true
            anchors.bottom: true
            anchors.left: true

            implicitWidth: 48
            color: "#202020"

            Text {
                anchors.centerIn: parent
                text: "noctis"
                color: "white"
            }
        }
    }
}
