#!/usr/bin/env bash
# tests/test_vpn_networkmanager.sh
# NetworkManager VPN adapters (commands/vpn/networkmanager.sh) against a
# stubbed nmcli: OpenVPN, WireGuard and other plugin connections split by
# kind, addressed by UUID, with nmcli's terse-mode escapes undone.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

export HOME="$WORKDIR/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_DATA_HOME="$HOME/.local/share"
export APHOTIC_DOTS_DIR="$ROOT"
mkdir -p "$HOME" "$WORKDIR/bin"

export NM_CALLS="$WORKDIR/nmcli.log"
export NM_ACTIVE="$WORKDIR/active"
printf 'aaaa-1\n' > "$NM_ACTIVE"

cat > "$WORKDIR/bin/nmcli" <<'NMCLI'
#!/usr/bin/env bash
echo "$*" >> "$NM_CALLS"
case "$*" in
    "-t -f UUID,TYPE,NAME connection show")
        cat <<'ROWS'
aaaa-1:vpn:Office\: HQ
bbbb-2:wireguard:wg-home
cccc-3:802-11-wireless:Cafe
dddd-4:vpn:Legacy vpnc
eeee-5:wireguard:wg\\lab
ROWS
        ;;
    "-t -f UUID connection show --active") cat "$NM_ACTIVE" ;;
    "-g vpn.service-type connection show uuid aaaa-1") echo "org.freedesktop.NetworkManager.openvpn" ;;
    "-g vpn.service-type connection show uuid dddd-4") echo "org.freedesktop.NetworkManager.vpnc" ;;
    "connection up uuid "*|"connection down uuid "*) exit 0 ;;
    *) echo "unexpected nmcli call: $*" >&2; exit 9 ;;
esac
NMCLI
chmod +x "$WORKDIR/bin/nmcli"
export PATH="$WORKDIR/bin:$PATH"

APHOTIC="$ROOT/Configs/.local/bin/aphotic"
run() { bash "$APHOTIC" vpn "$@" 2>&1; }
provider() { jq -c --arg id "$1" '.providers[] | select(.id == $id)' <<<"$json"; }

# --- 1. list splits NM connections by kind ------------------------------
json="$(run list --json)" || fail "list --json failed: $json"
[[ "$(provider nm-openvpn)" == '{"id":"nm-openvpn","label":"OpenVPN (NetworkManager)","available":true,"connections":[{"id":"aaaa-1","name":"Office: HQ","active":true,"detail":""}]}' ]] \
    || fail "nm-openvpn: $(provider nm-openvpn)"
[[ "$(provider nm-wireguard | jq -c '.connections')" == '[{"id":"bbbb-2","name":"wg-home","active":false,"detail":""},{"id":"eeee-5","name":"wg\\lab","active":false,"detail":""}]' ]] \
    || fail "nm-wireguard: $(provider nm-wireguard)"
[[ "$(provider nm-vpn | jq -c '[.connections[].id]')" == '["dddd-4"]' ]] \
    || fail "nm-vpn should hold the non-OpenVPN plugin only: $(provider nm-vpn)"
grep -q "Cafe" <<<"$json" && fail "a Wi-Fi connection leaked into the VPN list"

out="$(run status)"
[[ "$out" == *"connected via OpenVPN (NetworkManager): Office: HQ"* ]] || fail "status: $out"

# --- 2. connect and disconnect by UUID ----------------------------------
: > "$NM_CALLS"
run connect --provider nm-wireguard bbbb-2 >/dev/null || fail "wireguard connect failed"
grep -qx "connection up uuid bbbb-2" "$NM_CALLS" || fail "connect did not bring bbbb-2 up: $(cat "$NM_CALLS")"

: > "$NM_CALLS"
out="$(run connect --provider nm-wireguard aaaa-1)" && fail "connecting an OpenVPN UUID through the WireGuard adapter should fail"
[[ "$out" == *"no NetworkManager wireguard connection"* ]] || fail "wrong-kind error unclear: $out"
grep -q "connection up" "$NM_CALLS" && fail "a refused connect still ran nmcli up"

: > "$NM_CALLS"
run disconnect --provider nm-openvpn >/dev/null || fail "openvpn disconnect-all failed"
grep -qx "connection down uuid aaaa-1" "$NM_CALLS" || fail "disconnect did not take aaaa-1 down: $(cat "$NM_CALLS")"

: > "$NM_CALLS"
out="$(run disconnect --provider nm-wireguard)"
[[ "$out" == *"not connected"* ]] || fail "disconnect with nothing active should say so: $out"
grep -q "connection down" "$NM_CALLS" && fail "disconnect ran nmcli down with nothing active"

printf 'aaaa-1\nbbbb-2\neeee-5\n' > "$NM_ACTIVE"
: > "$NM_CALLS"
run disconnect --provider nm-wireguard eeee-5 >/dev/null || fail "targeted disconnect failed"
[[ "$(grep -c "connection down" "$NM_CALLS")" -eq 1 ]] && grep -qx "connection down uuid eeee-5" "$NM_CALLS" \
    || fail "targeted disconnect should only take eeee-5 down: $(cat "$NM_CALLS")"

# --- 3. no nmcli, no provider -------------------------------------------
rm "$WORKDIR/bin/nmcli"
json="$(PATH="$WORKDIR/bin:/usr/bin:/bin" run list --json)"
if command -v nmcli >/dev/null 2>&1 && PATH="$WORKDIR/bin:/usr/bin:/bin" command -v nmcli >/dev/null 2>&1; then
    echo "SKIP: a real nmcli is installed, availability check not exercised"
else
    [[ "$(provider nm-openvpn | jq -c '[.available, .connections]')" == '[false,[]]' ]] \
        || fail "without nmcli the adapter should be unavailable: $(provider nm-openvpn)"
fi

# --- 4. Vpn.qml re-reads on NetworkManager's own change events ----------
VPN_CODE="$(sed 's://.*::' "$ROOT/Configs/quickshell/aphotic/services/Vpn.qml")"
grep -q "target: Nmcli" <<<"$VPN_CODE" || fail "Vpn.qml does not follow Nmcli's VPN change events"
grep -q "function onVpnActiveChanged" <<<"$VPN_CODE" || fail "Vpn.qml misses onVpnActiveChanged"

echo "PASS: tests/test_vpn_networkmanager.sh"
