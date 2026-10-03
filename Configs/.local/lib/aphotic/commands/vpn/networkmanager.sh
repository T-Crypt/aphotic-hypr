#!/usr/bin/env bash
# VPN adapters: NetworkManager OpenVPN, WireGuard, and any other NM VPN
# plugin, all through nmcli. Connections are addressed by UUID.

APHOTIC_VPN_ADAPTERS+=(nm-openvpn nm-wireguard nm-vpn)

# UUID<TAB>KIND<TAB>ACTIVE<TAB>NAME for every NM VPN connection, where
# KIND is openvpn, wireguard or vpn. UUID and TYPE never contain a colon,
# so NAME is everything after the second one, with nmcli's \: and \\
# escapes undone.
_aphotic_vpn_nm_rows() {
    local all active line uuid type name kind service
    all="$(nmcli -t -f UUID,TYPE,NAME connection show 2>/dev/null)" || return 0
    active="$(nmcli -t -f UUID connection show --active 2>/dev/null)" || active=""
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        uuid="${line%%:*}"
        line="${line#*:}"
        type="${line%%:*}"
        name="${line#*:}"
        name="${name//\\:/:}"
        name="${name//\\\\/\\}"
        case "$type" in
            wireguard) kind=wireguard ;;
            vpn)
                service="$(nmcli -g vpn.service-type connection show uuid "$uuid" 2>/dev/null)" || service=""
                if [[ "$service" == *.openvpn ]]; then kind=openvpn; else kind=vpn; fi
                ;;
            *) continue ;;
        esac
        if grep -qxF -- "$uuid" <<<"$active"; then
            printf '%s\t%s\ttrue\t%s\n' "$uuid" "$kind" "$name"
        else
            printf '%s\t%s\tfalse\t%s\n' "$uuid" "$kind" "$name"
        fi
    done <<<"$all"
}

_aphotic_vpn_nm_list() {
    local want="$1" uuid kind active name
    while IFS=$'\t' read -r uuid kind active name; do
        [[ "$kind" == "$want" ]] || continue
        jq -nc --arg id "$uuid" --arg name "$name" --argjson active "$active" \
            '{id: $id, name: $name, active: $active}'
    done < <(_aphotic_vpn_nm_rows)
}

_aphotic_vpn_nm_owns() {
    local want="$1" id="$2" uuid kind active name
    while IFS=$'\t' read -r uuid kind active name; do
        [[ "$kind" == "$want" && "$uuid" == "$id" ]] && return 0
    done < <(_aphotic_vpn_nm_rows)
    return 1
}

_aphotic_vpn_nm_connect() {
    local want="$1" id="$2"
    if ! _aphotic_vpn_nm_owns "$want" "$id"; then
        aphotic_err "no NetworkManager ${want} connection with UUID ${id}"
        return 1
    fi
    nmcli connection up uuid "$id" >/dev/null && aphotic_ok "connected"
}

# With no id, takes down every active connection of this kind.
_aphotic_vpn_nm_disconnect() {
    local want="$1" id="${2:-}" uuid kind active name targets=()
    while IFS=$'\t' read -r uuid kind active name; do
        [[ "$kind" == "$want" && "$active" == true ]] || continue
        [[ -z "$id" || "$uuid" == "$id" ]] && targets+=("$uuid")
    done < <(_aphotic_vpn_nm_rows)
    if [[ ${#targets[@]} -eq 0 ]]; then
        aphotic_log "not connected"
        return 0
    fi
    for uuid in "${targets[@]}"; do
        nmcli connection down uuid "$uuid" >/dev/null || return 1
    done
    aphotic_ok "disconnected"
}

_aphotic_vpn_nm_available() {
    command -v nmcli >/dev/null 2>&1
}

_aphotic_vpn_nm_openvpn_label() { echo "OpenVPN (NetworkManager)"; }
_aphotic_vpn_nm_openvpn_available() { _aphotic_vpn_nm_available; }
_aphotic_vpn_nm_openvpn_list() { _aphotic_vpn_nm_list openvpn; }
_aphotic_vpn_nm_openvpn_connect() { _aphotic_vpn_nm_connect openvpn "$1"; }
_aphotic_vpn_nm_openvpn_disconnect() { _aphotic_vpn_nm_disconnect openvpn "${1:-}"; }

_aphotic_vpn_nm_wireguard_label() { echo "WireGuard (NetworkManager)"; }
_aphotic_vpn_nm_wireguard_available() { _aphotic_vpn_nm_available; }
_aphotic_vpn_nm_wireguard_list() { _aphotic_vpn_nm_list wireguard; }
_aphotic_vpn_nm_wireguard_connect() { _aphotic_vpn_nm_connect wireguard "$1"; }
_aphotic_vpn_nm_wireguard_disconnect() { _aphotic_vpn_nm_disconnect wireguard "${1:-}"; }

_aphotic_vpn_nm_vpn_label() { echo "Other VPN (NetworkManager)"; }
_aphotic_vpn_nm_vpn_available() { _aphotic_vpn_nm_available; }
_aphotic_vpn_nm_vpn_list() { _aphotic_vpn_nm_list vpn; }
_aphotic_vpn_nm_vpn_connect() { _aphotic_vpn_nm_connect vpn "$1"; }
_aphotic_vpn_nm_vpn_disconnect() { _aphotic_vpn_nm_disconnect vpn "${1:-}"; }
