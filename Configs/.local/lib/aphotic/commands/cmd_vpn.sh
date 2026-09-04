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
# @cmd.opt: status              | Show whether the managed OpenVPN process is up
# @cmd.opt: connect [path]      | Connect, using the given .ovpn or the saved config path
# @cmd.opt: disconnect          | Disconnect
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

_aphotic_vpn_status() {
    local pid; pid="$(_aphotic_vpn_pid)"
    if [[ -n "$pid" ]]; then
        aphotic_ok "connected (pid ${pid})"
    else
        aphotic_log "not connected"
    fi
}

_aphotic_vpn_connect() {
    local config_path="${1:-}"
    [[ -n "$config_path" ]] || config_path="$(_aphotic_vpn_config_path)"

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

_aphotic_vpn_autostart() {
    local auto; auto="$(_aphotic_vpn_auto_connect)"
    [[ "$auto" == "true" ]] || return 0
    _aphotic_vpn_connect
}

aphotic_cmd_vpn() {
    local sub="${1:-status}"; shift || true
    case "$sub" in
        status) _aphotic_vpn_status ;;
        connect) _aphotic_vpn_connect "$@" ;;
        disconnect) _aphotic_vpn_disconnect ;;
        autostart) _aphotic_vpn_autostart ;;
        ""|-h|--help)
            cat <<HELP
Usage: aphotic vpn <status|connect [path]|disconnect>

  status           Show whether the managed OpenVPN process is up.
  connect [path]   Connect, using [path] or Settings' saved vpnConfigPath.
  disconnect       Disconnect.
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
