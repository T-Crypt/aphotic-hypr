#!/usr/bin/env bash
# tests/test_bar_cli.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

OK_LOG="$WORKDIR/ok.log"
ERR_LOG="$WORKDIR/err.log"

aphotic_ok()  { echo "$*" >> "$OK_LOG"; }
aphotic_err() { echo "$*" >> "$ERR_LOG"; }
aphotic_require() {
    command -v "$1" >/dev/null 2>&1 || { aphotic_err "missing dependency: $1"; return 1; }
}

source "$ROOT/Configs/.local/lib/aphotic/commands/cmd_bar.sh"

# --- fake `qs` executable on PATH, logging whatever args it was called with ---
export QS_CALL_LOG="$WORKDIR/qs_calls.log"
mkdir -p "$WORKDIR/bin"
cat > "$WORKDIR/bin/qs" <<'EOF'
#!/usr/bin/env bash
echo "$*" > "$QS_CALL_LOG"
exit 0
EOF
chmod +x "$WORKDIR/bin/qs"
REAL_PATH="$PATH"
export PATH="$WORKDIR/bin:$PATH"

reset_logs() {
    : > "$OK_LOG"
    : > "$ERR_LOG"
    rm -f "$QS_CALL_LOG"
}

# 1. Each valid style calls through to `qs ... setStyle <name>` and reports ok.
for style in full dock taskbar minimal capsule; do
    reset_logs
    rc=0
    aphotic_cmd_bar style "$style" || rc=$?
    [[ "$rc" -eq 0 ]] || fail "style '$style' expected exit 0, got $rc"
    [[ -f "$QS_CALL_LOG" ]] || fail "style '$style' did not invoke qs"
    grep -q -- "-c aphotic ipc call bar setStyle $style" "$QS_CALL_LOG" \
        || fail "style '$style' called qs with unexpected args: $(cat "$QS_CALL_LOG")"
    grep -q "$style" "$OK_LOG" || fail "style '$style' did not report success via aphotic_ok"
    [[ -s "$ERR_LOG" ]] && fail "style '$style' unexpectedly wrote to aphotic_err: $(cat "$ERR_LOG")"
done

# 2. Bogus style name -- fails loudly, never touches qs.
reset_logs
rc=0
aphotic_cmd_bar style bogus || rc=$?
[[ "$rc" -ne 0 ]] || fail "expected nonzero exit for bogus style"
[[ -f "$QS_CALL_LOG" ]] && fail "bogus style must not invoke qs"
grep -q "unknown style 'bogus'" "$ERR_LOG" || fail "expected an unknown-style error, got: $(cat "$ERR_LOG")"

# 3. No argument -- usage error, nonzero exit, no qs call.
reset_logs
rc=0
aphotic_cmd_bar style || rc=$?
[[ "$rc" -ne 0 ]] || fail "expected nonzero exit for missing style argument"
[[ -f "$QS_CALL_LOG" ]] && fail "missing-argument case must not invoke qs"
grep -q "usage: aphotic bar style" "$ERR_LOG" || fail "expected a usage error, got: $(cat "$ERR_LOG")"

# 4. cycle calls through to `qs ... cycleStyle`.
reset_logs
rc=0
aphotic_cmd_bar cycle || rc=$?
[[ "$rc" -eq 0 ]] || fail "cycle expected exit 0, got $rc"
[[ -f "$QS_CALL_LOG" ]] || fail "cycle did not invoke qs"
grep -q -- "-c aphotic ipc call bar cycleStyle" "$QS_CALL_LOG" \
    || fail "cycle called qs with unexpected args: $(cat "$QS_CALL_LOG")"
grep -qi "cycle" "$OK_LOG" || fail "cycle did not report success via aphotic_ok"

# 5. `qs` missing from PATH entirely -- aphotic_require fails loudly and
#    neither internal helper ever attempts the ipc call.
reset_logs
mkdir -p "$WORKDIR/emptybin"
BASH_BIN="$(command -v bash)"
PATH="$WORKDIR/emptybin" "$BASH_BIN" -c '
    set -euo pipefail
    aphotic_ok()  { echo "$*" >> "'"$OK_LOG"'"; }
    aphotic_err() { echo "$*" >> "'"$ERR_LOG"'"; }
    aphotic_require() {
        command -v "$1" >/dev/null 2>&1 || { aphotic_err "missing dependency: $1"; return 1; }
    }
    source "'"$ROOT"'/Configs/.local/lib/aphotic/commands/cmd_bar.sh"

    rc=0
    _aphotic_bar_style full || rc=$?
    [[ "$rc" -ne 0 ]] || exit 91

    rc=0
    _aphotic_bar_cycle || rc=$?
    [[ "$rc" -ne 0 ]] || exit 92
' && style_cycle_rc=0 || style_cycle_rc=$?
case "$style_cycle_rc" in
    0) ;;
    91) fail "_aphotic_bar_style expected nonzero exit when qs is missing from PATH" ;;
    92) fail "_aphotic_bar_cycle expected nonzero exit when qs is missing from PATH" ;;
    *) fail "unexpected error running the qs-missing subshell (exit $style_cycle_rc)" ;;
esac
[[ -f "$QS_CALL_LOG" ]] && fail "qs must never be invoked when aphotic_require qs fails"
grep -q "missing dependency: qs" "$ERR_LOG" || fail "expected an aphotic_require failure message, got: $(cat "$ERR_LOG")"

export PATH="$REAL_PATH"

echo "PASS: bar CLI style/cycle dispatch, bogus/missing-arg rejection, and qs-missing guard"
