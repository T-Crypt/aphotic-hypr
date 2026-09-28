#!/usr/bin/env bash
# VPN adapter: Mullvad. One connection, the daemon's tunnel.
#
# `mullvad status` is plain text and its layout changed across releases:
# older ones print "Connected to <relay> in <city>, <country>", newer ones
# print "Connected" with indented "Relay:" and "Visible location:" lines.
# Both are read.

APHOTIC_VPN_ADAPTERS+=(mullvad)

_aphotic_vpn_mullvad_label() {
    echo "Mullvad"
}

_aphotic_vpn_mullvad_available() {
    command -v mullvad >/dev/null 2>&1
}

_aphotic_vpn_mullvad_list() {
    local out first active=false relay location name detail
    out="$(mullvad status 2>/dev/null)" || return 0
    first="$(head -n1 <<<"$out")"
    [[ "$first" == Connected* ]] && active=true
    relay="$(sed -nE \
        -e 's/^[[:space:]]*Relay:[[:space:]]*([^[:space:]]+).*/\1/p' \
        -e 's/^Connected to ([^[:space:]]+).*/\1/p' <<<"$out" | head -n1)"
    location="$(sed -nE \
        -e 's/^[[:space:]]*Visible location:[[:space:]]*([^.]+)\..*/\1/p' \
        -e 's/^[[:space:]]*Visible location:[[:space:]]*([^.]+)$/\1/p' \
        -e 's/^Connected to [^[:space:]]+ in (.+)$/\1/p' <<<"$out" | head -n1)"
    name="Mullvad"
    detail=""
    if [[ "$active" == true ]]; then
        [[ -n "$relay" ]] && name="$relay"
        detail="$location"
    elif [[ "$first" == Blocked* ]]; then
        detail="blocked"
    fi
    jq -nc --arg name "$name" --argjson active "$active" --arg detail "$detail" \
        '{id: "mullvad", name: $name, active: $active, detail: $detail}'
}

_aphotic_vpn_mullvad_connect() {
    mullvad connect >/dev/null && aphotic_ok "connecting"
}

_aphotic_vpn_mullvad_disconnect() {
    mullvad disconnect >/dev/null && aphotic_ok "disconnected"
}
