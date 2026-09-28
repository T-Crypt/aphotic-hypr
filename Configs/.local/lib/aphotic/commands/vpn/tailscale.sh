#!/usr/bin/env bash
# VPN adapter: Tailscale. One connection, the current tailnet.

APHOTIC_VPN_ADAPTERS+=(tailscale)

_aphotic_vpn_tailscale_label() {
    echo "Tailscale"
}

_aphotic_vpn_tailscale_available() {
    command -v tailscale >/dev/null 2>&1
}

# No row when tailscaled is not running: `tailscale up` could not succeed.
_aphotic_vpn_tailscale_list() {
    local json
    json="$(tailscale status --json 2>/dev/null)" || return 0
    jq -c '
        select(type == "object" and (.BackendState | type) == "string")
        | {id: "tailnet",
           name: (.CurrentTailnet.Name // .MagicDNSSuffix // "Tailscale"),
           active: (.BackendState == "Running"),
           detail: (if .BackendState == "Running" then ((.Self.TailscaleIPs // [])[0] // "")
                    elif .BackendState == "NeedsLogin" then "needs login"
                    else "" end)}' <<<"$json" 2>/dev/null || true
}

# `tailscale up` on a node that needs login prints a URL and blocks until
# someone opens it, which would hang the shell's action forever.
_aphotic_vpn_tailscale_connect() {
    local state
    state="$(tailscale status --json 2>/dev/null | jq -r '.BackendState // ""' 2>/dev/null)" || state=""
    if [[ "$state" == "NeedsLogin" || "$state" == "NoState" ]]; then
        aphotic_err "Tailscale needs a login first -- run 'tailscale login' in a terminal"
        return 1
    fi
    timeout 60 tailscale up && aphotic_ok "connected"
}

_aphotic_vpn_tailscale_disconnect() {
    tailscale down && aphotic_ok "disconnected"
}
