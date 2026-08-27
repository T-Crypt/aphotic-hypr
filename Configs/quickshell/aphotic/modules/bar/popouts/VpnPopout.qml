import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    spacing: Tokens.spacing.medium

    Component.onCompleted: Nmcli.getVpnStatus(() => {})

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "vpn_key"
            color: Nmcli.vpnActive ? Colours.palette.m3primary : Colours.palette.m3onSurface
            fill: Nmcli.vpnActive ? 1 : 0
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("VPN")
        }

        StyledText {
            text: Nmcli.vpnActive ? qsTr("Connected") : qsTr("Not connected")
            color: Nmcli.vpnActive ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }
    }

    StyledText {
        visible: Nmcli.vpnActive && Nmcli.vpnConnectionName.length > 0
        text: Nmcli.vpnConnectionName
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    StyledText {
        visible: !Nmcli.vpnActive
        Layout.preferredWidth: 220
        text: qsTr("No active VPN connection. Connect via nmcli/NetworkManager to see it here.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
        wrapMode: Text.Wrap
    }
}
