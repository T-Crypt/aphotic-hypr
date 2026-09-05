import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    spacing: Tokens.spacing.medium

    NetworkUsageWatch {}

    component SpeedRow: RowLayout {
        required property string icon
        required property string label
        required property var formatted
        required property var history

        spacing: Tokens.spacing.small

        MaterialIcon {
            text: icon
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.small
        }

        StyledText {
            text: label
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: `${formatted.value.toFixed(1)} ${formatted.unit}`
            color: Colours.palette.m3onSurface
            font: Tokens.font.body.medium
        }

        Row {
            readonly property real maxVal: Math.max(1, ...history, 1024)

            spacing: 1

            Repeater {
                model: history

                Rectangle {
                    required property real modelData

                    width: 3
                    height: Math.max(2, modelData / parent.maxVal * 24)
                    anchors.bottom: parent.bottom
                    color: Colours.palette.m3primary
                    opacity: 0.7
                }
            }
        }
    }

    SpeedRow {
        Layout.fillWidth: true
        icon: "arrow_downward"
        label: qsTr("Down")
        formatted: NetworkUsage.formatBytes(NetworkUsage.downloadSpeed)
        history: NetworkUsage.downloadBuffer.values
    }

    SpeedRow {
        Layout.fillWidth: true
        icon: "arrow_upward"
        label: qsTr("Up")
        formatted: NetworkUsage.formatBytes(NetworkUsage.uploadSpeed)
        history: NetworkUsage.uploadBuffer.values
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: {
            const down = NetworkUsage.formatBytesTotal(NetworkUsage.downloadTotal);
            const up = NetworkUsage.formatBytesTotal(NetworkUsage.uploadTotal);
            return qsTr("Total: %1 %2 down, %3 %4 up").arg(down.value.toFixed(1)).arg(down.unit).arg(up.value.toFixed(1)).arg(up.unit);
        }
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
    }
}
