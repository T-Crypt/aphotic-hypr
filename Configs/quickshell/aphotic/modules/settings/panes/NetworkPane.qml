pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Network")
        font: Tokens.font.title.large
    }

    StyledText {
        text: qsTr("VPN")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Connects a raw OpenVPN profile directly (aphotic vpn) — separate from any VPN connection managed through NetworkManager/nmcli, which still shows up in the bar's own network popout.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "vpn_key"
            label: qsTr("Config file")
            description: qsTr(".ovpn path")

            StyledRect {
                implicitWidth: 260
                implicitHeight: 32
                radius: Tokens.rounding.full
                color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                TextInput {
                    id: configInput

                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    text: Settings.vpnConfigPath

                    Keys.onReturnPressed: {
                        Settings.vpnConfigPath = configInput.text.trim();
                        configInput.focus = false;
                    }

                    StyledText {
                        visible: configInput.text.length === 0
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("~/vpn/client.ovpn")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        SettingsToggleRow {
            icon: "power_settings_new"
            label: qsTr("Auto-connect")
            description: qsTr("Connect automatically at login")
            checked: Settings.vpnAutoConnect
            onToggled: state => Settings.vpnAutoConnect = state
        }

        SettingsRow {
            icon: "cable"
            label: qsTr("Status")
            description: Vpn.connected ? qsTr("Connected") : qsTr("Not connected")

            StyledRect {
                id: actionButton

                implicitWidth: actionLabel.implicitWidth + Tokens.padding.large * 2
                implicitHeight: 32
                radius: Tokens.rounding.full
                color: Colours.tPalette.m3surfaceContainer
                opacity: actionButton.enabled ? 1 : 0.5

                readonly property bool enabled: !Vpn.busy && (Vpn.connected || Settings.vpnConfigPath.length > 0)

                StyledText {
                    id: actionLabel
                    anchors.centerIn: parent
                    text: {
                        if (Vpn.busy)
                            return Vpn.connected ? qsTr("Disconnecting…") : qsTr("Connecting…");
                        return Vpn.connected ? qsTr("Disconnect") : qsTr("Connect");
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    disabled: !actionButton.enabled
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: actionButton.enabled
                    onClicked: Vpn.connected ? Vpn.disconnectVpn() : Vpn.connectVpn(Settings.vpnConfigPath)
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Needs passwordless sudo for the underlying openvpn process — see commands/README.md if Connect/Disconnect just warn and no-op.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }
}
