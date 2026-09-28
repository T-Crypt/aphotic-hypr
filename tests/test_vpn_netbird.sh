#!/usr/bin/env bash
# tests/test_vpn_netbird.sh
# NetBird adapter (commands/vpn/netbird.sh) against a stubbed `netbird`:
# status --json maps to one row, up/down act on it, and a peer that needs
# login is refused instead of starting an SSO flow that blocks.
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

export NB_CALLS="$WORKDIR/netbird.log"
export NB_STATUS="$WORKDIR/status.json"
export NB_RC="$WORKDIR/status.rc"
echo 0 > "$NB_RC"

cat > "$WORKDIR/bin/netbird" <<'NB'
#!/usr/bin/env bash
echo "$*" >> "$NB_CALLS"
case "$1" in
    status) cat "$NB_STATUS"; exit "$(cat "$NB_RC")" ;;
    up|down) exit 0 ;;
    *) echo "unexpected netbird call: $*" >&2; exit 9 ;;
esac
NB
chmod +x "$WORKDIR/bin/netbird"
export PATH="$WORKDIR/bin:$PATH"

APHOTIC="$ROOT/Configs/.local/bin/aphotic"
run() { bash "$APHOTIC" vpn "$@" 2>&1; }
row() { run list --json | jq -c '.providers[] | select(.id == "netbird")'; }

# --- 1. status --json -> one row ----------------------------------------
cat > "$NB_STATUS" <<'JSON'
{"peers":{"total":3,"connected":2},"management":{"url":"https://api.netbird.io:443","connected":true},
 "signal":{"url":"https://signal.netbird.io:443","connected":true},"netbirdIp":"100.92.1.7/16","fqdn":"box.netbird.cloud"}
JSON
[[ "$(row)" == '{"id":"netbird","label":"NetBird","available":true,"connections":[{"id":"netbird","name":"api.netbird.io","active":true,"detail":"100.92.1.7"}]}' ]] \
    || fail "connected peer: $(row)"
[[ "$(run status)" == *"connected via NetBird: api.netbird.io"* ]] || fail "status: $(run status)"

echo '{"management":{"url":"https://nb.example.org","connected":false},"netbirdIp":"100.92.1.7/16"}' > "$NB_STATUS"
[[ "$(row | jq -c '.connections')" == '[{"id":"netbird","name":"nb.example.org","active":false,"detail":""}]' ]] \
    || fail "disconnected peer: $(row)"

echo 'Daemon status: NeedsLogin' > "$NB_STATUS"
echo 1 > "$NB_RC"
[[ "$(row | jq -c '.connections')" == '[{"id":"netbird","name":"NetBird","active":false,"detail":"needs login"}]' ]] \
    || fail "needs-login peer: $(row)"

echo 'failed to connect to daemon' > "$NB_STATUS"
row | jq -e '.available and .connections == []' >/dev/null || fail "daemon down should list no connection: $(row)"

# --- 2. up/down ----------------------------------------------------------
echo '{"management":{"connected":false}}' > "$NB_STATUS"
echo 0 > "$NB_RC"
: > "$NB_CALLS"
run connect --provider netbird netbird >/dev/null || fail "connect failed"
grep -qx "up" "$NB_CALLS" || fail "connect did not run 'netbird up': $(cat "$NB_CALLS")"
: > "$NB_CALLS"
run disconnect --provider netbird >/dev/null || fail "disconnect failed"
grep -qx "down" "$NB_CALLS" || fail "disconnect did not run 'netbird down': $(cat "$NB_CALLS")"

# --- 3. needs login: refuse, never run `up` -----------------------------
echo 'Daemon status: NeedsLogin' > "$NB_STATUS"
echo 1 > "$NB_RC"
: > "$NB_CALLS"
out="$(run connect --provider netbird netbird)" && fail "connect on NeedsLogin should fail"
[[ "$out" == *"needs a login"* ]] || fail "needs-login error unclear: $out"
grep -qx "up" "$NB_CALLS" && fail "connect ran 'netbird up' on a peer that needs login"

# --- 4. no netbird binary: unavailable ----------------------------------
rm "$WORKDIR/bin/netbird"
if PATH="$WORKDIR/bin:/usr/bin:/bin" command -v netbird >/dev/null 2>&1; then
    echo "SKIP: a real netbird is installed, availability check not exercised"
else
    out="$(PATH="$WORKDIR/bin:/usr/bin:/bin" bash "$APHOTIC" vpn list --json | jq -c '.providers[] | select(.id == "netbird") | [.available, .connections]')"
    [[ "$out" == '[false,[]]' ]] || fail "without netbird the adapter should be unavailable: $out"
fi

echo "PASS: tests/test_vpn_netbird.sh"
