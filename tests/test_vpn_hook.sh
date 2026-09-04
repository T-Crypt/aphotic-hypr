#!/usr/bin/env bash
# tests/test_vpn_hook.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

HOOK="$ROOT/Configs/.local/lib/aphotic/vpn-hook.sh"
MARKER="$WORKDIR/state/vpn-connected"

[[ -x "$HOOK" ]] || fail "vpn-hook.sh is not executable (openvpn will refuse to run it)"

# --- 1. up creates the marker, world-readable ---------------------------
rc=0
env APHOTIC_VPN_MARKER="$MARKER" script_type=up "$HOOK" || rc=$?
[[ "$rc" -eq 0 ]] || fail "up hook exited $rc, expected 0"
[[ -f "$MARKER" ]] || fail "up hook did not create the marker"
mode="$(stat -c '%a' "$MARKER")"
[[ "$mode" == "644" ]] || fail "marker mode is $mode, expected 644 (root writes it, the user reads it)"

# --- 2. up is idempotent ------------------------------------------------
rc=0
env APHOTIC_VPN_MARKER="$MARKER" script_type=up "$HOOK" || rc=$?
[[ "$rc" -eq 0 ]] || fail "second up hook exited $rc, expected 0"
[[ -f "$MARKER" ]] || fail "second up hook removed the marker"

# --- 3. down removes it, and is idempotent ------------------------------
rc=0
env APHOTIC_VPN_MARKER="$MARKER" script_type=down "$HOOK" || rc=$?
[[ "$rc" -eq 0 ]] || fail "down hook exited $rc, expected 0"
[[ ! -e "$MARKER" ]] || fail "down hook did not remove the marker"

rc=0
env APHOTIC_VPN_MARKER="$MARKER" script_type=down "$HOOK" || rc=$?
[[ "$rc" -eq 0 ]] || fail "down hook on a missing marker exited $rc, expected 0"

# --- 4. any other script_type is a no-op, still exit 0 ------------------
for st in "" route-up tls-verify; do
    rc=0
    env APHOTIC_VPN_MARKER="$MARKER" script_type="$st" "$HOOK" || rc=$?
    [[ "$rc" -eq 0 ]] || fail "hook with script_type='$st' exited $rc, expected 0"
    [[ ! -e "$MARKER" ]] || fail "hook with script_type='$st' touched the marker"
done

# --- 5. an unwritable marker path must NOT fail the tunnel --------------
# openvpn treats a nonzero --up as fatal, so a state dir it cannot write
# has to degrade to "the shell never shows connected", never to a torn
# down VPN.
rc=0
env APHOTIC_VPN_MARKER="/proc/definitely-not-writable/vpn-connected" script_type=up "$HOOK" || rc=$?
[[ "$rc" -eq 0 ]] || fail "up hook on an unwritable path exited $rc, expected 0 (would kill the tunnel)"

# --- 6. cmd_vpn.sh hands openvpn the flags the hook needs ---------------
OK_LOG="$WORKDIR/ok.log"
ERR_LOG="$WORKDIR/err.log"
aphotic_log()  { echo "$*" >> "$OK_LOG"; }
aphotic_ok()   { echo "$*" >> "$OK_LOG"; }
aphotic_warn() { echo "$*" >> "$ERR_LOG"; }
aphotic_err()  { echo "$*" >> "$ERR_LOG"; }
aphotic_require() {
    command -v "$1" >/dev/null 2>&1 || { aphotic_err "missing dependency: $1"; return 1; }
}

export APHOTIC_STATE_HOME="$WORKDIR/state"
mkdir -p "$APHOTIC_STATE_HOME" "$WORKDIR/bin"

export SUDO_CALL_LOG="$WORKDIR/sudo_calls.log"
cat > "$WORKDIR/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
# `sudo -n true` is the passwordless probe cmd_vpn.sh makes first.
[[ "${1:-}" == "-n" ]] && exit 0
printf '%s\n' "$*" > "$SUDO_CALL_LOG"
exit 0
SUDO
cat > "$WORKDIR/bin/openvpn" <<'OVPN'
#!/usr/bin/env bash
exit 0
OVPN
# No aphotic-vpn process exists, so connect proceeds rather than
# short-circuiting on "already connected".
cat > "$WORKDIR/bin/pgrep" <<'PGREP'
#!/usr/bin/env bash
exit 1
PGREP
chmod +x "$WORKDIR/bin/sudo" "$WORKDIR/bin/openvpn" "$WORKDIR/bin/pgrep"
export PATH="$WORKDIR/bin:$PATH"

source "$ROOT/Configs/.local/lib/aphotic/commands/cmd_vpn.sh"

CONFIG="$WORKDIR/test.ovpn"
: > "$CONFIG"

rc=0
_aphotic_vpn_connect "$CONFIG" || rc=$?
[[ "$rc" -eq 0 ]] || fail "connect exited $rc, expected 0"
[[ -f "$SUDO_CALL_LOG" ]] || fail "connect never invoked sudo openvpn"
call="$(cat "$SUDO_CALL_LOG")"

case "$call" in
    *"--script-security 2"*) ;;
    *) fail "connect omitted --script-security 2; --up/--down would silently never fire. Got: $call" ;;
esac
case "$call" in
    *"--setenv APHOTIC_VPN_MARKER ${APHOTIC_STATE_HOME}/vpn-connected"*) ;;
    *) fail "connect did not pass the marker path via --setenv. Got: $call" ;;
esac
case "$call" in
    *"--up ${ROOT}/Configs/.local/lib/aphotic/vpn-hook.sh"*) ;;
    *) fail "connect did not pass --up <vpn-hook.sh>. Got: $call" ;;
esac
case "$call" in
    *"--down ${ROOT}/Configs/.local/lib/aphotic/vpn-hook.sh"*) ;;
    *) fail "connect did not pass --down <vpn-hook.sh>. Got: $call" ;;
esac

# --- 7. status detection must not have regressed into a poll -----------
# Comments are stripped first: this file's own header explains what the
# poll used to be, so a raw grep would match the prose describing the
# thing it is checking is gone.
VPN_CODE="$WORKDIR/Vpn.code.qml"
sed 's://.*::' "$ROOT/Configs/quickshell/aphotic/services/Vpn.qml" > "$VPN_CODE"

if grep -Eq '^[[:space:]]*Timer[[:space:]]*\{' "$VPN_CODE"; then
    fail "Vpn.qml declares a Timer again -- status detection is the marker FileView, not a poll"
fi
if grep -q 'pgrep' "$VPN_CODE"; then
    fail "Vpn.qml still shells out to pgrep for status"
fi
if grep -Eq '^[[:space:]]*FileView[[:space:]]*\{' "$VPN_CODE"; then :; else
    fail "Vpn.qml has no FileView watching the marker"
fi
if grep -q 'vpn-connected' "$VPN_CODE"; then :; else
    fail "Vpn.qml does not reference the vpn-connected marker vpn-hook.sh writes"
fi

echo "PASS: tests/test_vpn_hook.sh"
