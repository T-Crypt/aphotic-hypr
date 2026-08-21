import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.utils

ColumnLayout {
    id: root

    spacing: Tokens.spacing.medium

    Component.onCompleted: Nmcli.getNetworks(() => {})

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: Nmcli.wifiEnabled ? "wifi" : "wifi_off"
            color: Colours.palette.m3onSurface
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Wi-Fi")
        }

        Item {
            implicitWidth: 44
            implicitHeight: 24

            StateLayer {
                radius: Tokens.rounding.full
                color: Nmcli.wifiEnabled ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh
                onClicked: Nmcli.toggleWifi(() => {})
            }
        }
    }

    StyledText {
        visible: Nmcli.hasAvailableEthernet
        text: Nmcli.activeEthernet?.connected ? qsTr("Ethernet connected (%1)").arg(Nmcli.activeEthernet.iface) : qsTr("Ethernet available")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    Repeater {
        model: {
            const list = Nmcli.networks.slice();
            list.sort((a, b) => (b.active ? 1 : 0) - (a.active ? 1 : 0) || b.strength - a.strength);
            return list.slice(0, 6);
        }

        Item {
            id: netRow

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: netLabel.implicitHeight + Tokens.padding.small * 2

            StateLayer {
                radius: Tokens.rounding.small
                onClicked: {
                    if (netRow.modelData.active)
                        return;
                    Nmcli.connectToNetwork(netRow.modelData.ssid, "", netRow.modelData.bssid, result => {
                        if (result.needsPassword)
                            Toaster.toast(qsTr("Password required"), qsTr("%1 needs a password to connect").arg(netRow.modelData.ssid), "lock");
                    });
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: Icons.getNetworkIcon(netRow.modelData.strength, netRow.modelData.isSecure)
                    color: netRow.modelData.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    id: netLabel
                    Layout.fillWidth: true
                    text: netRow.modelData.ssid
                    color: netRow.modelData.active ? Colours.palette.m3primary : Colours.palette.m3onSurface
                    elide: Text.ElideRight
                }

                MaterialIcon {
                    visible: netRow.modelData.isSecure
                    text: "lock"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
}
