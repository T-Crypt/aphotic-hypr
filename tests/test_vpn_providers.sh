#!/usr/bin/env bash
# tests/test_vpn_providers.sh
# The VPN provider contract in cmd_vpn.sh: adapters are discovered from
# one directory, `list --json` is the one shape services/Vpn.qml reads,
# and connect/disconnect --provider route to the named adapter only.
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
mkdir -p "$HOME"

APHOTIC="$ROOT/Configs/.local/bin/aphotic"
ADAPTERS="$WORKDIR/adapters"
CALLS="$WORKDIR/calls.log"
export CALLS
mkdir -p "$ADAPTERS"

cat > "$ADAPTERS/alpha.sh" <<'ADAPTER'
APHOTIC_VPN_ADAPTERS+=(alpha-net)
_aphotic_vpn_alpha_net_label() { echo "Alpha"; }
_aphotic_vpn_alpha_net_available() { return 0; }
_aphotic_vpn_alpha_net_list() {
    echo '{"id":"home","name":"Home","active":true,"detail":"10.0.0.2"}'
    echo '{"id":"work","active":false}'
    echo 'not json'
    echo '{"name":"no id"}'
}
_aphotic_vpn_alpha_net_connect() { echo "alpha connect $1" >> "$CALLS"; }
_aphotic_vpn_alpha_net_disconnect() { echo "alpha disconnect ${1:-}" >> "$CALLS"; }
ADAPTER

cat > "$ADAPTERS/beta.sh" <<'ADAPTER'
APHOTIC_VPN_ADAPTERS+=(beta)
_aphotic_vpn_beta_label() { echo "Beta"; }
_aphotic_vpn_beta_available() { return 1; }
_aphotic_vpn_beta_list() { echo '{"id":"x","active":true}'; }
_aphotic_vpn_beta_connect() { echo "beta connect $1" >> "$CALLS"; }
_aphotic_vpn_beta_disconnect() { echo "beta disconnect" >> "$CALLS"; }
ADAPTER

cat > "$ADAPTERS/broken.sh" <<'ADAPTER'
APHOTIC_VPN_ADAPTERS+=(broken)
_aphotic_vpn_broken_label() { echo "Broken"; }
_aphotic_vpn_broken_available() { return 0; }
_aphotic_vpn_broken_list() { echo 'garbage'; return 3; }
ADAPTER

run() { APHOTIC_VPN_ADAPTER_DIR="$ADAPTERS" bash "$APHOTIC" vpn "$@" 2>&1; }

# --- 1. list --json: discovery order, normalisation, availability -------
json="$(run list --json)" || fail "list --json exited nonzero: $json"
jq -e . >/dev/null <<<"$json" || fail "list --json is not JSON: $json"
[[ "$(jq -c '[.providers[].id]' <<<"$json")" == '["alpha-net","beta","broken"]' ]] \
    || fail "providers not discovered in file order: $json"
[[ "$(jq -c '.providers[0]' <<<"$json")" == '{"id":"alpha-net","label":"Alpha","available":true,"connections":[{"id":"home","name":"Home","active":true,"detail":"10.0.0.2"},{"id":"work","name":"work","active":false,"detail":""}]}' ]] \
    || fail "alpha provider not normalised to the contract: $(jq -c '.providers[0]' <<<"$json")"
[[ "$(jq -c '.providers[1]' <<<"$json")" == '{"id":"beta","label":"Beta","available":false,"connections":[]}' ]] \
    || fail "an unavailable provider must list no connections: $(jq -c '.providers[1]' <<<"$json")"
[[ "$(jq -c '.providers[2].connections' <<<"$json")" == '[]' ]] \
    || fail "a failing adapter should list nothing, not break the list"

# --- 2. human list and status -------------------------------------------
out="$(run list)"
[[ "$out" == *"Alpha [alpha-net]"* && "$out" == *"* Home (10.0.0.2)"* && "$out" == *"- work"* ]] \
    || fail "human list missing entries: $out"
[[ "$out" == *"Beta [beta] (not available)"* ]] || fail "human list should mark unavailable providers: $out"

out="$(run status)"
[[ "$out" == *"connected via Alpha: Home"* ]] || fail "status should name the active connection: $out"
[[ "$out" != *"Beta"* ]] || fail "status must ignore unavailable providers: $out"

# --- 3. connect/disconnect route to the named adapter only --------------
: > "$CALLS"
run connect --provider alpha-net work >/dev/null || fail "connect --provider exited nonzero"
run disconnect -p alpha-net home >/dev/null || fail "disconnect -p exited nonzero"
run disconnect --provider alpha-net >/dev/null || fail "disconnect without a name exited nonzero"
[[ "$(cat "$CALLS")" == $'alpha connect work\nalpha disconnect home\nalpha disconnect ' ]] \
    || fail "calls did not route to alpha: $(cat "$CALLS")"

# --- 4. refusals --------------------------------------------------------
: > "$CALLS"
out="$(run connect --provider nope x)" && fail "unknown provider should fail"
[[ "$out" == *"unknown vpn provider 'nope'"* && "$out" == *"alpha-net beta broken"* ]] \
    || fail "unknown provider error should list known ids: $out"
out="$(run connect --provider beta x)" && fail "unavailable provider should fail"
[[ "$out" == *"not available"* ]] || fail "unavailable provider error unclear: $out"
out="$(run connect --provider alpha-net)" && fail "connect without a name should fail"
[[ "$out" == *"usage"* ]] || fail "connect without a name should print usage: $out"
[[ ! -s "$CALLS" ]] || fail "a refused action still reached an adapter: $(cat "$CALLS")"

# --- 5. the shipped adapters load and are not top-level commands --------
json="$(bash "$APHOTIC" vpn list --json)" || fail "list with shipped adapters failed: $json"
jq -e '.providers | map(.id) | index("openvpn")' >/dev/null <<<"$json" \
    || fail "the OpenVPN profile adapter is missing: $json"
for f in "$ROOT"/Configs/.local/lib/aphotic/commands/vpn/*.sh; do
    bash -n "$f" || fail "$f does not parse"
    grep -q '^APHOTIC_VPN_ADAPTERS+=(' "$f" || fail "$f does not register an adapter"
done
out="$(bash "$APHOTIC" -s)"
grep -qx 'openvpn' <<<"$out" && fail "an adapter file leaked into the top-level command list"

# --- 6. OpenVPN profile adapter -----------------------------------------
BIN="$WORKDIR/bin"
mkdir -p "$BIN"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/openvpn"
chmod +x "$BIN/openvpn"
STATE="$XDG_STATE_HOME/aphotic"
mkdir -p "$STATE"

json="$(PATH="$BIN:$PATH" bash "$APHOTIC" vpn list --json)"
[[ "$(jq -c '.providers[] | select(.id == "openvpn")' <<<"$json")" == '{"id":"openvpn","label":"OpenVPN profile","available":true,"connections":[]}' ]] \
    || fail "openvpn with no config should list no connection: $json"

echo '{"vpnConfigPath":"~/vpn/lab.ovpn"}' > "$STATE/settings.json"
json="$(PATH="$BIN:$PATH" bash "$APHOTIC" vpn list --json)"
[[ "$(jq -c '.providers[] | select(.id == "openvpn") | .connections' <<<"$json")" == '[{"id":"profile","name":"lab.ovpn","active":false,"detail":""}]' ]] \
    || fail "openvpn should list the saved profile as inactive: $json"

: > "$STATE/vpn-connected"
json="$(PATH="$BIN:$PATH" bash "$APHOTIC" vpn list --json)"
[[ "$(jq -c '.providers[] | select(.id == "openvpn") | .connections[0].active' <<<"$json")" == 'true' ]] \
    || fail "the vpn-connected marker should mark the profile active: $json"

echo "PASS: tests/test_vpn_providers.sh"
