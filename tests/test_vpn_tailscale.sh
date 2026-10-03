#!/usr/bin/env bash
# tests/test_vpn_tailscale.sh
# Tailscale adapter (commands/vpn/tailscale.sh) against a stubbed
# `tailscale`: status --json maps to one tailnet row, up/down act on it,
# and a node that needs login is refused instead of hanging on `up`.
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

export TS_CALLS="$WORKDIR/tailscale.log"
export TS_STATUS="$WORKDIR/status.json"
export TS_STATUS_RC=0

cat > "$WORKDIR/bin/tailscale" <<'TS'
#!/usr/bin/env bash
echo "$*" >> "$TS_CALLS"
case "$1" in
    status) cat "$TS_STATUS"; exit "$TS_STATUS_RC" ;;
    up|down) exit 0 ;;
    *) echo "unexpected tailscale call: $*" >&2; exit 9 ;;
esac
TS
chmod +x "$WORKDIR/bin/tailscale"
export PATH="$WORKDIR/bin:$PATH"

APHOTIC="$ROOT/Configs/.local/bin/aphotic"
run() { bash "$APHOTIC" vpn "$@" 2>&1; }
row() { run list --json | jq -c '.providers[] | select(.id == "tailscale")'; }

# --- 1. status --json -> one tailnet row --------------------------------
cat > "$TS_STATUS" <<'JSON'
{"BackendState":"Running","Self":{"HostName":"box","TailscaleIPs":["100.101.102.103","fd7a:115c:a1e0::1"]},
 "CurrentTailnet":{"Name":"example.org","MagicDNSSuffix":"tail1234.ts.net"},"MagicDNSSuffix":"tail1234.ts.net"}
JSON
[[ "$(row)" == '{"id":"tailscale","label":"Tailscale","available":true,"connections":[{"id":"tailnet","name":"example.org","active":true,"detail":"100.101.102.103"}]}' ]] \
    || fail "running tailnet: $(row)"
[[ "$(run status)" == *"connected via Tailscale: example.org"* ]] || fail "status: $(run status)"

echo '{"BackendState":"Stopped","MagicDNSSuffix":"tail1234.ts.net"}' > "$TS_STATUS"
[[ "$(row | jq -c '.connections')" == '[{"id":"tailnet","name":"tail1234.ts.net","active":false,"detail":""}]' ]] \
    || fail "stopped tailnet: $(row)"

echo '{"BackendState":"NeedsLogin"}' > "$TS_STATUS"
[[ "$(row | jq -c '.connections')" == '[{"id":"tailnet","name":"Tailscale","active":false,"detail":"needs login"}]' ]] \
    || fail "needs-login tailnet: $(row)"

# tailscaled not running: exit nonzero, no row.
echo 'failed to connect to local tailscaled' > "$TS_STATUS"
TS_STATUS_RC=1 row | jq -e '.connections == [] and .available' >/dev/null \
    || fail "no tailscaled should list no connection"

# --- 2. up/down ----------------------------------------------------------
echo '{"BackendState":"Stopped"}' > "$TS_STATUS"
: > "$TS_CALLS"
run connect --provider tailscale tailnet >/dev/null || fail "connect failed"
grep -qx "up" "$TS_CALLS" || fail "connect did not run 'tailscale up': $(cat "$TS_CALLS")"

: > "$TS_CALLS"
run disconnect --provider tailscale >/dev/null || fail "disconnect failed"
grep -qx "down" "$TS_CALLS" || fail "disconnect did not run 'tailscale down': $(cat "$TS_CALLS")"

# --- 3. needs login: refuse, never run a blocking `up` ------------------
echo '{"BackendState":"NeedsLogin"}' > "$TS_STATUS"
: > "$TS_CALLS"
out="$(run connect --provider tailscale tailnet)" && fail "connect on NeedsLogin should fail"
[[ "$out" == *"tailscale login"* ]] || fail "needs-login error should point at 'tailscale login': $out"
grep -qx "up" "$TS_CALLS" && fail "connect ran 'tailscale up' on a node that needs login"

# --- 4. no tailscale binary: unavailable --------------------------------
rm "$WORKDIR/bin/tailscale"
if PATH="$WORKDIR/bin:/usr/bin:/bin" command -v tailscale >/dev/null 2>&1; then
    echo "SKIP: a real tailscale is installed, availability check not exercised"
else
    out="$(PATH="$WORKDIR/bin:/usr/bin:/bin" bash "$APHOTIC" vpn list --json | jq -c '.providers[] | select(.id == "tailscale") | [.available, .connections]')"
    [[ "$out" == '[false,[]]' ]] || fail "without tailscale the adapter should be unavailable: $out"
fi

echo "PASS: tests/test_vpn_tailscale.sh"
