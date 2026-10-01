pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.config
import qs.components
import qs.services

// Wi-Fi, Bluetooth and DND in the shelf's width. Each toggle flips current
// state through the service the dashboard tiles already use -- these own no
// configuration and start no watcher of their own.
Flickable {
    id: root

    contentWidth: width
    contentHeight: layout.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    ColumnLayout {
        id: layout

        width: root.width
        spacing: Tokens.spacing.extraSmall

        Repeater {
            model: [
                { icon: Nmcli.wifiEnabled ? "wifi" : "wifi_off", label: qsTr("Wi-Fi"),
                    active: Nmcli.wifiEnabled, toggle: () => Nmcli.toggleWifi(() => {}) },
                { icon: Bluetooth.defaultAdapter?.enabled ? "bluetooth" : "bluetooth_disabled", label: qsTr("Bluetooth"),
                    active: Bluetooth.defaultAdapter?.enabled ?? false,
                    toggle: () => { if (Bluetooth.defaultAdapter)
                        Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled; } },
                { icon: DoNotDisturb.enabled ? "notifications_off" : "notifications", label: qsTr("DND"),
                    active: DoNotDisturb.enabled, toggle: () => DoNotDisturb.toggle() }
            ]

            delegate: Item {
                id: tile

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: Tokens.sizes.bar.innerWidth

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.full
                    color: tile.modelData.active ? Colours.layer(Colours.palette.m3primary, 0.18) : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                }

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: tile.modelData.toggle()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        Layout.preferredWidth: Tokens.sizes.bar.innerWidth * 0.6
                        text: tile.modelData.icon
                        fontStyle: Tokens.font.icon.medium
                        fill: tile.modelData.active ? 1 : 0
                        color: tile.modelData.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: tile.modelData.label
                        elide: Text.ElideRight
                        color: tile.modelData.active ? Colours.palette.m3primary : Colours.palette.m3onSurface
                        font: Tokens.font.label.small
                    }
                }
            }
        }
    }
}