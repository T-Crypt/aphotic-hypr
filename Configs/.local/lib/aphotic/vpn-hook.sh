#!/usr/bin/env bash
# lib/aphotic/vpn-hook.sh
# openvpn's --up/--down hook, one file for both halves: openvpn puts
# "up" or "down" in $script_type, and the two halves are a touch and an
# rm of the same marker. Two scripts would just be the same branch split
# across two files.
#
# The marker is how services/Vpn.qml knows the tunnel is up -- a FileView
# watching this path, no poll of any kind. cmd_vpn.sh passes the path in
# through openvpn's --setenv, because openvpn runs this as root with
# root's environment: APHOTIC_STATE_HOME is not set here and $HOME is not
# the user's. The fallback below only covers a hand-run invocation.
#
# 644 on the marker: openvpn runs this as root, the shell reading it runs
# as the user.
#
# Never exits nonzero. openvpn treats a failing --up as fatal and tears
# the tunnel down, so a status marker this script could not write must
# not be able to kill a working connection.

marker="${APHOTIC_VPN_MARKER:-}"
if [[ -z "$marker" ]]; then
    marker="${XDG_STATE_HOME:-${HOME:-/root}/.local/state}/aphotic/vpn-connected"
fi

case "${script_type:-}" in
    up)
        mkdir -p "$(dirname "$marker")" 2>/dev/null || true
        touch "$marker" 2>/dev/null || true
        chmod 644 "$marker" 2>/dev/null || true
        ;;
    down)
        rm -f "$marker" 2>/dev/null || true
        ;;
esac

exit 0
