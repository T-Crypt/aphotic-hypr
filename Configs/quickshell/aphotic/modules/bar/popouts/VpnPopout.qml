import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    spacing: Tokens.spacing.medium

    Component.onCompleted: Vpn.refresh()

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "vpn_key"
            color: Vpn.status.connected ? Colours.signal : Colours.ink
            fill: Vpn.status.connected ? 1 : 0
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("VPN").toUpperCase()
            font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
        }

        StyledText {
            text: Vpn.status.connected ? qsTr("Connected") : qsTr("Not connected")
            color: Vpn.status.connected ? Colours.ink : Colours.inkMuted
            font: Tokens.font.label.medium
        }
    }

    StyledText {
        visible: Vpn.status.connected && (Vpn.status.primary?.name ?? "").length > 0
        text: Vpn.status.primary?.name ?? ""
        color: Colours.inkMuted
        font: Tokens.font.label.medium
    }

    StyledText {
        visible: !Vpn.status.connected
        Layout.preferredWidth: 220
        text: qsTr("No active VPN connection.")
        color: Colours.inkMuted
        font: Tokens.font.label.small
        wrapMode: Text.Wrap
    }
}
