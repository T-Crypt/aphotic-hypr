#!/usr/bin/env bash
# tests/test_vpn_mullvad.sh
# Mullvad adapter (commands/vpn/mullvad.sh) against a stubbed `mullvad`:
# both `mullvad status` text layouts map to one row, connect/disconnect
# run the daemon's own commands.
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

export MV_CALLS="$WORKDIR/mullvad.log"
export MV_STATUS="$WORKDIR/status.txt"
export MV_RC="$WORKDIR/status.rc"
echo 0 > "$MV_RC"

cat > "$WORKDIR/bin/mullvad" <<'MV'
#!/usr/bin/env bash
echo "$*" >> "$MV_CALLS"
case "$1" in
    status) cat "$MV_STATUS"; exit "$(cat "$MV_RC")" ;;
    connect|disconnect) exit 0 ;;
    *) echo "unexpected mullvad call: $*" >&2; exit 9 ;;
esac
MV
chmod +x "$WORKDIR/bin/mullvad"
export PATH="$WORKDIR/bin:$PATH"

APHOTIC="$ROOT/Configs/.local/bin/aphotic"
run() { bash "$APHOTIC" vpn "$@" 2>&1; }
conns() { run list --json | jq -c '.providers[] | select(.id == "mullvad") | .connections'; }

# --- 1. both status layouts ----------------------------------------------
cat > "$MV_STATUS" <<'TXT'
Connected
    Relay:                  se-got-wg-001
    Features:               Quantum Resistance
    Visible location:       Sweden, Gothenburg. IPv4: 185.213.154.1
TXT
[[ "$(conns)" == '[{"id":"mullvad","name":"se-got-wg-001","active":true,"detail":"Sweden, Gothenburg"}]' ]] \
    || fail "new layout, connected: $(conns)"
[[ "$(run status)" == *"connected via Mullvad: se-got-wg-001"* ]] || fail "status: $(run status)"

echo 'Connected to se-mma-wg-003 in Malmo, Sweden' > "$MV_STATUS"
[[ "$(conns)" == '[{"id":"mullvad","name":"se-mma-wg-003","active":true,"detail":"Malmo, Sweden"}]' ]] \
    || fail "old layout, connected: $(conns)"

printf 'Connecting\n    Relay:   se-got-wg-001\n' > "$MV_STATUS"
[[ "$(conns)" == '[{"id":"mullvad","name":"Mullvad","active":false,"detail":""}]' ]] \
    || fail "connecting is not connected: $(conns)"

echo 'Disconnected' > "$MV_STATUS"
[[ "$(conns)" == '[{"id":"mullvad","name":"Mullvad","active":false,"detail":""}]' ]] \
    || fail "disconnected: $(conns)"

echo 'Blocked: The device is offline' > "$MV_STATUS"
[[ "$(conns)" == '[{"id":"mullvad","name":"Mullvad","active":false,"detail":"blocked"}]' ]] \
    || fail "blocked: $(conns)"

echo 'Error: Management RPC server or client error' > "$MV_STATUS"
echo 1 > "$MV_RC"
[[ "$(conns)" == '[]' ]] || fail "daemon down should list no connection: $(conns)"
echo 0 > "$MV_RC"

# --- 2. connect/disconnect -----------------------------------------------
echo 'Disconnected' > "$MV_STATUS"
: > "$MV_CALLS"
run connect --provider mullvad mullvad >/dev/null || fail "connect failed"
grep -qx "connect" "$MV_CALLS" || fail "connect did not run 'mullvad connect': $(cat "$MV_CALLS")"
: > "$MV_CALLS"
run disconnect --provider mullvad >/dev/null || fail "disconnect failed"
grep -qx "disconnect" "$MV_CALLS" || fail "disconnect did not run 'mullvad disconnect': $(cat "$MV_CALLS")"

# --- 3. no mullvad binary: unavailable ----------------------------------
rm "$WORKDIR/bin/mullvad"
if PATH="$WORKDIR/bin:/usr/bin:/bin" command -v mullvad >/dev/null 2>&1; then
    echo "SKIP: a real mullvad is installed, availability check not exercised"
else
    out="$(PATH="$WORKDIR/bin:/usr/bin:/bin" bash "$APHOTIC" vpn list --json | jq -c '.providers[] | select(.id == "mullvad") | [.available, .connections]')"
    [[ "$out" == '[false,[]]' ]] || fail "without mullvad the adapter should be unavailable: $out"
fi

echo "PASS: tests/test_vpn_mullvad.sh"
