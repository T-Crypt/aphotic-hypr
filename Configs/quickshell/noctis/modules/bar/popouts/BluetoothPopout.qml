import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.config
import qs.components
import qs.services
import qs.utils

ColumnLayout {
    id: root

    spacing: Tokens.spacing.medium

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: Bluetooth.defaultAdapter?.enabled ? "bluetooth" : "bluetooth_disabled"
            color: Colours.palette.m3onSurface
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Bluetooth")
        }

        Item {
            implicitWidth: 44
            implicitHeight: 24

            StateLayer {
                radius: Tokens.rounding.full
                color: Bluetooth.defaultAdapter?.enabled ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh
                onClicked: {
                    if (Bluetooth.defaultAdapter)
                        Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
                }
            }
        }
    }

    Repeater {
        // ScriptModel (not a plain array binding) so unchanged entries
        // keep delegate identity across re-evaluations -- see
        // NetworkPopout.qml's identical fix for why.
        model: ScriptModel {
            values: {
                const list = Bluetooth.devices.values.slice();
                list.sort((a, b) => (b.connected ? 1 : 0) - (a.connected ? 1 : 0));
                return list.slice(0, 8);
            }
        }

        Item {
            id: devRow

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: devLabel.implicitHeight + Tokens.padding.small * 2

            StateLayer {
                radius: Tokens.rounding.small
                onClicked: devRow.modelData.connected ? devRow.modelData.disconnect() : devRow.modelData.connect()
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: Icons.getBluetoothIcon(devRow.modelData.icon)
                    color: devRow.modelData.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    id: devLabel
                    Layout.fillWidth: true
                    text: devRow.modelData.name
                    color: devRow.modelData.connected ? Colours.palette.m3primary : Colours.palette.m3onSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    visible: devRow.modelData.connected
                    text: qsTr("Connected")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }
            }
        }
    }

    StyledText {
        visible: Bluetooth.devices.values.length === 0
        text: qsTr("No devices")
        color: Colours.palette.m3onSurfaceVariant
    }
}
