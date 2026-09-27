pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "aphotic-greeter"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    readonly property color hairline: Qt.alpha(Colours.mutedTextColor, 0.22)

    Wallpaper {
        id: wallpaper

        anchors.fill: parent
        visible: false
    }

    // The wallpaper, softly blurred once; nothing here animates, so the blur
    // renders a single time rather than every frame.
    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        blurEnabled: true
        blur: 0.55
        blurMax: 48
        saturation: -0.1
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(Colours.background, 0.35)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(Colours.background, 0.8)
            }
        }
    }

    GreeterContent {
        id: content

        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40
        auth: auth
    }

    // Signal line along the bottom, lit under the login card.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56
        height: 1
        color: root.hairline

        Rectangle {
            x: content.x
            width: content.width
            height: 2
            y: -1
            radius: 1
            color: Colours.primary
        }
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        spacing: 8

        Repeater {
            model: [
                { label: qsTr("RESTART"), command: ["systemctl", "reboot"] },
                { label: qsTr("SHUT DOWN"), command: ["systemctl", "poweroff"] }
            ]

            Rectangle {
                id: powerButton

                required property var modelData

                width: powerLabel.implicitWidth + 28
                height: 30
                radius: height / 2
                color: powerMouse.containsMouse ? Qt.alpha(Colours.textColor, 0.08) : "transparent"
                border.width: 1
                border.color: root.hairline

                Text {
                    id: powerLabel

                    anchors.centerIn: parent
                    text: powerButton.modelData.label
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.4
                    color: Colours.mutedTextColor
                }

                MouseArea {
                    id: powerMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(powerButton.modelData.command)
                }
            }
        }
    }

    GreeterAuth {
        id: auth
    }
}
