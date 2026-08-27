import QtQuick
import qs.config
import qs.components
import qs.services

MaterialIcon {
    id: root

    required property color colour

    text: "vpn_key"
    color: Nmcli.vpnActive ? Colours.palette.m3primary : root.colour
    fill: Nmcli.vpnActive ? 1 : 0
}
