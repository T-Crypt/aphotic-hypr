import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    // Fixed width so Layout.fillWidth + elide on the CPU/disk secondary
    // lines actually constrain their text instead of reporting their
    // full unelided implicitWidth upward -- with no width imposed here,
    // a long CPU model name grew the whole popout wider than
    // BarWindow.qml's fixed popout-flyout budget and got clipped by the
    // layer-shell surface's own bounds (real bug, not hypothetical).
    width: 280

    spacing: Tokens.spacing.medium

    component UsageBar: StyledRect {
        id: usageBar

        property real perc: 0
        property color barColour: Colours.palette.m3primary

        Layout.fillWidth: true
        implicitHeight: 4
        radius: Tokens.rounding.full
        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

        StyledRect {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * usageBar.perc
            radius: Tokens.rounding.full
            color: usageBar.barColour
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "memory"
            color: Colours.palette.m3primary
            fill: 1
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    text: qsTr("CPU")
                    font: Tokens.font.title.medium
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    text: `${Math.round(SystemUsage.cpuPerc * 100)}%`
                    font: Tokens.font.title.medium
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: !!SystemUsage.cpuName
                text: SystemUsage.cpuTemp > 0 ? qsTr("%1 · %2°C").arg(SystemUsage.cpuName).arg(Math.round(SystemUsage.cpuTemp)) : SystemUsage.cpuName
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
                elide: Text.ElideRight
            }
        }
    }

    UsageBar {
        perc: SystemUsage.cpuPerc
        barColour: Colours.palette.m3primary
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "memory_alt"
            color: Colours.palette.m3tertiary
            fill: 1
        }

        StyledText {
            text: qsTr("Memory")
            font: Tokens.font.title.medium
        }

        Item {
            Layout.fillWidth: true
        }

        StyledText {
            text: {
                const usedFmt = SystemUsage.formatKib(SystemUsage.memUsed);
                const totalFmt = SystemUsage.formatKib(SystemUsage.memTotal);
                return qsTr("%1 / %2 %3 · %4%").arg(usedFmt.value.toFixed(1)).arg(totalFmt.value.toFixed(1)).arg(totalFmt.unit).arg(Math.round(SystemUsage.memPerc * 100));
            }
            font: Tokens.font.title.medium
        }
    }

    UsageBar {
        perc: SystemUsage.memPerc
        barColour: Colours.palette.m3tertiary
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        visible: SystemUsage.disks.length > 0

        StyledText {
            text: qsTr("Storage")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        Repeater {
            model: SystemUsage.disks

            ColumnLayout {
                id: diskRow

                required property var modelData

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: diskRow.modelData.mount
                        elide: Text.ElideMiddle
                    }

                    StyledText {
                        text: {
                            const usedFmt = SystemUsage.formatKib(diskRow.modelData.used);
                            const totalFmt = SystemUsage.formatKib(diskRow.modelData.total);
                            return qsTr("%1 / %2 %3 · %4%").arg(usedFmt.value.toFixed(1)).arg(totalFmt.value.toFixed(1)).arg(totalFmt.unit).arg(Math.round(diskRow.modelData.perc * 100));
                        }
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                    }
                }

                UsageBar {
                    perc: diskRow.modelData.perc
                    barColour: Colours.palette.m3secondary
                }
            }
        }
    }
}
