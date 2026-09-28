import QtQuick
import QtQuick.Layouts
import Quickshell
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
            text: Settings.barSignal ? qsTr("Wi-Fi").toUpperCase() : qsTr("Wi-Fi")
            font: Settings.barSignal ? Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build() : Tokens.font.body.small
        }

        Item {
            implicitWidth: 44
            implicitHeight: 24

            Rectangle {
                visible: Settings.barSignal
                anchors.fill: parent
                radius: Tokens.rounding.full
                color: Nmcli.wifiEnabled ? Qt.alpha(Colours.palette.m3primary, 0.18) : Colours.signalStyle.raised
                border.width: 1
                border.color: Nmcli.wifiEnabled ? Colours.palette.m3primary : Colours.signalStyle.hairline
            }

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
        // Wrapped in ScriptModel (rather than binding model: directly to a
        // freshly sorted/sliced array) so unchanged entries keep their
        // delegate identity across re-evaluations -- a plain array binding
        // reads as a full model reset to Repeater, destroying and
        // recreating every delegate (losing hover/press state) on every
        // network-list change instead of diffing just what moved.
        model: ScriptModel {
            values: {
                const list = Nmcli.networks.slice();
                list.sort((a, b) => (b.active ? 1 : 0) - (a.active ? 1 : 0) || b.strength - a.strength);
                return list.slice(0, 6);
            }
        }

        Item {
            id: netRow

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: netLabel.implicitHeight + Tokens.padding.small * 2

            StateLayer {
                radius: Settings.barSignal ? Tokens.rounding.medium : Tokens.rounding.small
                color: Settings.barSignal ? (netRow.modelData.active ? Colours.palette.m3primary : Colours.signalStyle.hover) : Colours.palette.m3onSurface
                stateOpacity: Settings.barSignal ? (netRow.modelData.active ? (containsMouse ? 0.22 : 0.14) : (containsMouse ? 1 : 0)) : (containsMouse ? 0.08 : 0)
                onClicked: {
                    if (netRow.modelData.active)
                        return;
                    Nmcli.connectToNetwork(netRow.modelData.ssid, "", netRow.modelData.bssid, result => {
                        if (result.needsPassword)
                            Toaster.toast(qsTr("Password required"), qsTr("%1 needs a password to connect").arg(netRow.modelData.ssid), "lock");
                    });
                }
            }

            Rectangle {
                visible: Settings.barSignal && netRow.modelData.active
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: parent.height - Tokens.padding.small * 2
                radius: Tokens.rounding.full
                color: Colours.signalStyle.accentLine
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
                    color: Settings.barSignal ? (netRow.modelData.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant) : (netRow.modelData.active ? Colours.palette.m3primary : Colours.palette.m3onSurface)
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
