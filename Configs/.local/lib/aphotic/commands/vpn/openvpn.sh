#!/usr/bin/env bash
# VPN adapter: the raw OpenVPN profile cmd_vpn.sh manages.

APHOTIC_VPN_ADAPTERS+=(openvpn)

_aphotic_vpn_openvpn_label() {
    echo "OpenVPN profile"
}

_aphotic_vpn_openvpn_available() {
    command -v openvpn >/dev/null 2>&1
}

_aphotic_vpn_openvpn_list() {
    local path active=false
    path="$(_aphotic_vpn_config_path)"
    [[ -f "$APHOTIC_VPN_MARKER_FILE" ]] && active=true
    [[ -n "$path" || "$active" == true ]] || return 0
    jq -nc --arg name "$(basename "${path:-openvpn}")" --argjson active "$active" \
        '{id: "profile", name: $name, active: $active}'
}

_aphotic_vpn_openvpn_connect() {
    _aphotic_vpn_connect
}

_aphotic_vpn_openvpn_disconnect() {
    _aphotic_vpn_disconnect
}
