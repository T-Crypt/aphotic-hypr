import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.config
import qs.components
import qs.services

// Wi-Fi/Bluetooth/DND one-shot toggles -- deliberately not the deferred
// Network/Bluetooth Settings pages (config-ownership conflicts, see
// ROADMAP_FEATURES.md): these just flip current state via nmcli/the
// native Bluetooth adapter/DoNotDisturb, they never own or persist any
// config themselves. No airplane-mode tile -- there's no single reliable
// "is airplane mode on" concept to read back on a desktop (only wifi+bt
// individually), and a tile that fakes combined state would drift out of
// sync the moment either one changes independently, so it's dropped
// rather than shipped wrong.
Item {
    id: root

    implicitWidth: layout.implicitWidth + Tokens.padding.large * 2
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    RowLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Tokens.spacing.large

        component ToggleTile: Item {
            id: tile

            required property string icon
            required property bool active
            required property string label

            signal clicked

            implicitWidth: Math.max(56, tileColumn.implicitWidth + Tokens.padding.medium * 2)
            implicitHeight: tileColumn.implicitHeight + Tokens.padding.medium * 2

            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.medium
                color: tile.active ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

                Behavior on color {
                    CAnim {}
                }
            }

            StateLayer {
                radius: Tokens.rounding.medium
                onClicked: tile.clicked()
            }

            ColumnLayout {
                id: tileColumn

                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall / 2

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: tile.icon
                    color: tile.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                    fill: tile.active ? 1 : 0
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: tile.label
                    color: tile.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
            }
        }

        ToggleTile {
            icon: Nmcli.wifiEnabled ? "wifi" : "wifi_off"
            active: Nmcli.wifiEnabled
            label: qsTr("Wi-Fi")
            onClicked: Nmcli.toggleWifi(() => {})
        }

        ToggleTile {
            icon: Bluetooth.defaultAdapter?.enabled ? "bluetooth" : "bluetooth_disabled"
            active: Bluetooth.defaultAdapter?.enabled ?? false
            label: qsTr("Bluetooth")
            onClicked: {
                if (Bluetooth.defaultAdapter)
                    Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
            }
        }

        ToggleTile {
            icon: DoNotDisturb.enabled ? "notifications_off" : "notifications"
            active: DoNotDisturb.enabled
            label: qsTr("DND")
            onClicked: DoNotDisturb.toggle()
        }
    }
}
