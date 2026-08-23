pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    spacing: Tokens.spacing.small / 2

    function copy(label: string, value: string): void {
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", value]);
        Quickshell.execDetached(["notify-send", "-a", "aphotic", `${label} copied`, value]);
    }

    StyledText {
        text: qsTr("Host info")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    Repeater {
        model: [
            { label: qsTr("Hostname"), value: HostInfo.hostname },
            { label: qsTr("IP address"), value: HostInfo.ipAddress || qsTr("No connection") }
        ]

        StyledRect {
            required property var modelData

            Layout.fillWidth: true
            Layout.preferredHeight: row.implicitHeight + Tokens.padding.medium
            implicitWidth: row.implicitWidth + Tokens.padding.medium * 2
            radius: Tokens.rounding.normal
            color: "transparent"

            StateLayer {
                anchors.fill: parent
                disabled: !modelData.value || modelData.value === qsTr("No connection")
                onClicked: root.copy(modelData.label, modelData.value)
            }

            RowLayout {
                id: row

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.small
                spacing: Tokens.spacing.small

                StyledText {
                    text: modelData.label
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: modelData.value
                    font: Tokens.font.mono.medium
                }

                MaterialIcon {
                    text: "content_copy"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Click a row to copy")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }
}
