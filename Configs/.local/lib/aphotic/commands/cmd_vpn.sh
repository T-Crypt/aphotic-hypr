#!/usr/bin/env bash
# aphotic vpn — connect/disconnect a raw OpenVPN profile (see
# ROADMAP_FEATURES.md's PART C for the resolved design: shells out to the
# raw `openvpn` binary directly, not openvpn3 or a NetworkManager plugin,
# since only `openvpn` is installed (profiles/layers/exploit-network.toml,
# an offensive-security/CTF context — HTB/THM-style VPN access, not a
# general-purpose always-on VPN layer).
#
# Deliberately separate from services/Nmcli.qml's existing `vpnActive`
# bar status — that's NetworkManager's own VPN connection list (e.g. a
# WireGuard connection managed via nmcli), a different mechanism this
# command doesn't touch or reflect. A raw `openvpn` process started here
# won't show up there.
# @cmd: vpn
# @cmd.desc: Connect/disconnect an OpenVPN profile
# @cmd.group: CONFIG
# @cmd.opt: status              | Show every active VPN connection, across providers
# @cmd.opt: list [--json]       | List VPN providers and their connections
# @cmd.opt: connect [path]      | Connect, using the given .ovpn or the saved config path
# @cmd.opt: connect --provider <id> [name] | Connect through one provider adapter
# @cmd.opt: disconnect [--provider <id> [name]] | Disconnect
# @cmd.opt: autostart           | Connect only if Settings.vpnAutoConnect is true (called from startup.lua)
#
# State (which .ovpn, auto-connect preference) lives in Settings.qml's
# own persisted state, not a profile toml — this is user runtime state,
# not an install-time choice (see PART C's resolved config-location
# decision).

APHOTIC_VPN_SETTINGS_FILE="${APHOTIC_STATE_HOME}/settings.json"
APHOTIC_VPN_LOG_FILE="${APHOTIC_STATE_HOME}/vpn.log"
# Distinctive --daemon tag, not a real progname change -- lets pgrep/pkill
# -f match only openvpn processes this command started, without needing to
# track a pidfile (root-written, would need care to keep readable) or grant
# sudo a blanket `kill` scoped to nothing more specific than "any PID".
APHOTIC_VPN_DAEMON_TAG="aphotic-vpn"
# Written by vpn-hook.sh on tunnel up, removed on tunnel down. This is
# what services/Vpn.qml watches, so the shell learns the state from
# openvpn's own hooks instead of polling for the process.
APHOTIC_VPN_MARKER_FILE="${APHOTIC_STATE_HOME}/vpn-connected"
APHOTIC_VPN_HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vpn-hook.sh"

# Provider contract. Each file in APHOTIC_VPN_ADAPTER_DIR appends its id
# to APHOTIC_VPN_ADAPTERS and defines, with the id's dashes as
# underscores:
#   _aphotic_vpn_<id>_label                 one-line display name
#   _aphotic_vpn_<id>_available             exit 0 when usable here
#   _aphotic_vpn_<id>_list                  one JSON object per line:
#                                           {"id","name","active","detail"}
#   _aphotic_vpn_<id>_connect <name>
#   _aphotic_vpn_<id>_disconnect [name]
# `list --json` is the one shape services/Vpn.qml reads.
APHOTIC_VPN_ADAPTER_DIR="${APHOTIC_VPN_ADAPTER_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vpn}"
APHOTIC_VPN_ADAPTERS=()
_APHOTIC_VPN_ADAPTERS_LOADED=0

_aphotic_vpn_config_path() {
    [[ -f "$APHOTIC_VPN_SETTINGS_FILE" ]] || return 0
    jq -r '.vpnConfigPath // ""' "$APHOTIC_VPN_SETTINGS_FILE" 2>/dev/null
}

_aphotic_vpn_auto_connect() {
    [[ -f "$APHOTIC_VPN_SETTINGS_FILE" ]] || { echo "false"; return 0; }
    jq -r '.vpnAutoConnect // false' "$APHOTIC_VPN_SETTINGS_FILE" 2>/dev/null
}

_aphotic_vpn_pid() {
    # pgrep exits 1 on no match, which -- combined with the dispatcher's
    # `set -euo pipefail` -- would otherwise kill the whole CLI process
    # right here instead of just reporting "not connected".
    pgrep -f "$APHOTIC_VPN_DAEMON_TAG" 2>/dev/null | head -n1 || true
}

_aphotic_vpn_connect() {
    local config_path="${1:-}"
    [[ -n "$config_path" ]] || config_path="$(_aphotic_vpn_config_path)"

    # Settings stores the path as typed, so expand a file:// URL or a ~.
    config_path="${config_path/#file:\/\//}"
    config_path="${config_path/#\~/$HOME}"

    if [[ -z "$config_path" ]]; then
        aphotic_err "no VPN config set — pass a path, or set one in Settings → Network, or 'aphotic config' (vpnConfigPath)"
        return 1
    fi
    if [[ ! -f "$config_path" ]]; then
        aphotic_err "config not found: ${config_path}"
        return 1
    fi

    if [[ -n "$(_aphotic_vpn_pid)" ]]; then
        aphotic_warn "already connected"
        return 0
    fi

    aphotic_require openvpn || return 1

    if ! sudo -n true 2>/dev/null; then
        aphotic_warn "vpn connect needs passwordless sudo to run automatically (see commands/README.md); run 'sudo -v' first, then retry"
        return 1
    fi

    if [[ ! -x "$APHOTIC_VPN_HOOK" ]]; then
        aphotic_warn "vpn hook missing or not executable at ${APHOTIC_VPN_HOOK}; the shell will not see the connection"
    fi

    # --script-security 2 is required before openvpn will run a user
    # script at all; without it --up/--down are accepted and then never
    # fire. --setenv carries the marker path into root's script
    # environment, which is the only way the hook can know where the
    # user's state dir is.
    sudo openvpn --config "$config_path" --daemon "$APHOTIC_VPN_DAEMON_TAG" --log "$APHOTIC_VPN_LOG_FILE" \
        --script-security 2 \
        --setenv APHOTIC_VPN_MARKER "$APHOTIC_VPN_MARKER_FILE" \
        --up "$APHOTIC_VPN_HOOK" --down "$APHOTIC_VPN_HOOK" &&
        aphotic_ok "connecting via $(basename "$config_path") (see ${APHOTIC_VPN_LOG_FILE})"
}

_aphotic_vpn_disconnect() {
    if [[ -z "$(_aphotic_vpn_pid)" ]]; then
        aphotic_log "not connected"
        return 0
    fi

    if ! sudo -n true 2>/dev/null; then
        aphotic_warn "vpn disconnect needs passwordless sudo to run automatically (see commands/README.md); run 'sudo -v' first, then retry"
        return 1
    fi

    sudo pkill -f "$APHOTIC_VPN_DAEMON_TAG" && aphotic_ok "disconnected"
}

_aphotic_vpn_load_adapters() {
    [[ "$_APHOTIC_VPN_ADAPTERS_LOADED" -eq 1 ]] && return 0
    _APHOTIC_VPN_ADAPTERS_LOADED=1
    local f
    for f in "$APHOTIC_VPN_ADAPTER_DIR"/*.sh; do
        [[ -f "$f" ]] || continue
        # shellcheck source=/dev/null
        source "$f"
    done
}

_aphotic_vpn_fn() {
    printf '_aphotic_vpn_%s_%s' "${1//-/_}" "$2"
}

_aphotic_vpn_is_adapter() {
    local id
    for id in "${APHOTIC_VPN_ADAPTERS[@]}"; do
        [[ "$id" == "$1" ]] && return 0
    done
    return 1
}

# One adapter's connections, normalised to the contract. A line that is
# not a JSON object with a string id is dropped rather than failing the
# whole list, so one broken adapter cannot blank every other provider.
_aphotic_vpn_adapter_connections() {
    local out
    out="$("$(_aphotic_vpn_fn "$1" list)" 2>/dev/null)" || true
    printf '%s\n' "$out" | jq -cR '
        fromjson? | objects
        | select((.id | type) == "string" and .id != "")
        | {id,
           name: ((.name // .id) | tostring),
           active: (.active == true),
           detail: ((.detail // "") | tostring)}' | jq -cs '.'
}

_aphotic_vpn_provider_json() {
    local id="$1" label available=false connections='[]'
    label="$("$(_aphotic_vpn_fn "$id" label)" 2>/dev/null)" || label="$id"
    if "$(_aphotic_vpn_fn "$id" available)" >/dev/null 2>&1; then
        available=true
        connections="$(_aphotic_vpn_adapter_connections "$id")"
    fi
    jq -nc --arg id "$id" --arg label "${label:-$id}" --argjson available "$available" \
        --argjson connections "${connections:-[]}" \
        '{id: $id, label: $label, available: $available, connections: $connections}'
}

_aphotic_vpn_list_json() {
    _aphotic_vpn_load_adapters
    local id
    for id in "${APHOTIC_VPN_ADAPTERS[@]}"; do
        _aphotic_vpn_provider_json "$id"
    done | jq -cs '{providers: .}'
}

_aphotic_vpn_list() {
    local json
    json="$(_aphotic_vpn_list_json)"
    if [[ "${1:-}" == "--json" ]]; then
        printf '%s\n' "$json"
        return 0
    fi
    jq -r '.providers[]
        | "\(.label) [\(.id)]\(if .available then "" else " (not available)" end)",
          (.connections[] | "  \(if .active then "*" else "-" end) \(.name)\(if .detail != "" then " (\(.detail))" else "" end)")' \
        <<<"$json"
}

_aphotic_vpn_status() {
    local active
    active="$(_aphotic_vpn_list_json | jq -r '.providers[] | select(.available) | .label as $l
        | .connections[] | select(.active) | "\($l): \(.name)"')"
    if [[ -z "$active" ]]; then
        aphotic_log "not connected"
        return 0
    fi
    local line
    while IFS= read -r line; do
        aphotic_ok "connected via ${line}"
    done <<<"$active"
}

# connect|disconnect --provider <id> [name]
_aphotic_vpn_provider_action() {
    local action="$1" id="$2" name="${3:-}"
    _aphotic_vpn_load_adapters
    if [[ -z "$id" ]] || ! _aphotic_vpn_is_adapter "$id"; then
        aphotic_err "unknown vpn provider '${id}' -- one of: ${APHOTIC_VPN_ADAPTERS[*]}"
        return 1
    fi
    if ! "$(_aphotic_vpn_fn "$id" available)" >/dev/null 2>&1; then
        aphotic_err "vpn provider '${id}' is not available on this machine"
        return 1
    fi
    if [[ "$action" == "connect" && -z "$name" ]]; then
        aphotic_err "usage: aphotic vpn connect --provider ${id} <name>"
        return 1
    fi
    "$(_aphotic_vpn_fn "$id" "$action")" "$name"
}

_aphotic_vpn_autostart() {
    local auto; auto="$(_aphotic_vpn_auto_connect)"
    [[ "$auto" == "true" ]] || return 0
    _aphotic_vpn_connect
}

aphotic_cmd_vpn() {
    local sub="${1:-status}"; shift || true
    case "$sub" in
        status) _aphotic_vpn_status ;;
        list) _aphotic_vpn_list "$@" ;;
        connect|disconnect)
            if [[ "${1:-}" == "--provider" || "${1:-}" == "-p" ]]; then
                _aphotic_vpn_provider_action "$sub" "${2:-}" "${3:-}"
            elif [[ "$sub" == "connect" ]]; then
                _aphotic_vpn_connect "$@"
            else
                _aphotic_vpn_disconnect
            fi
            ;;
        autostart) _aphotic_vpn_autostart ;;
        ""|-h|--help)
            cat <<HELP
Usage: aphotic vpn <status|list|connect|disconnect> [args]

  status           Show every active VPN connection, across providers.
  list [--json]    List VPN providers and their connections.
  connect [path]   Connect the OpenVPN profile, using [path] or Settings'
                   saved vpnConfigPath.
  connect --provider <id> <name>
                   Connect <name> through one provider (see 'list').
  disconnect [--provider <id> [name]]
                   Disconnect the OpenVPN profile, or one provider.
  autostart        Connect only if Settings.vpnAutoConnect is true (called
                   from startup.lua, not meant to be run by hand).
HELP
            ;;
        *)
            aphotic_err "unknown vpn subcommand: ${sub}"
            return 1
            ;;
    esac
}
