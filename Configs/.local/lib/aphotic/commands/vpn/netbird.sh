#!/usr/bin/env bash
# VPN adapter: NetBird. One connection, the peer's management network.

APHOTIC_VPN_ADAPTERS+=(netbird)

_aphotic_vpn_netbird_label() {
    echo "NetBird"
}

_aphotic_vpn_netbird_available() {
    command -v netbird >/dev/null 2>&1
}

_aphotic_vpn_netbird_status() {
    netbird status --json 2>&1
}

_aphotic_vpn_netbird_needs_login() {
    grep -q "NeedsLogin" <<<"$1"
}

# No row when the daemon is down: `netbird up` could not succeed.
_aphotic_vpn_netbird_list() {
    local out
    out="$(_aphotic_vpn_netbird_status)" || {
        _aphotic_vpn_netbird_needs_login "$out" \
            && jq -nc '{id: "netbird", name: "NetBird", active: false, detail: "needs login"}'
        return 0
    }
    jq -c '
        select(type == "object")
        | (.management.url // "" | sub("^[a-z]+://"; "") | sub("[:/].*$"; "")) as $host
        | {id: "netbird",
           name: (if $host != "" then $host else "NetBird" end),
           active: (.management.connected == true),
           detail: (if .management.connected == true then (.netbirdIp // "" | sub("/.*$"; "")) else "" end)}' \
        <<<"$out" 2>/dev/null || true
}

# `netbird up` on a peer that needs login starts an SSO flow and waits for
# it, which would hang the shell's action; refuse, and bound `up` anyway.
_aphotic_vpn_netbird_connect() {
    local out
    out="$(_aphotic_vpn_netbird_status)" || true
    if _aphotic_vpn_netbird_needs_login "$out"; then
        aphotic_err "NetBird needs a login first -- run 'netbird up' in a terminal"
        return 1
    fi
    timeout 60 netbird up >/dev/null && aphotic_ok "connected"
}

_aphotic_vpn_netbird_disconnect() {
    netbird down >/dev/null && aphotic_ok "disconnected"
}
