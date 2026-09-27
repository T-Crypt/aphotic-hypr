#!/usr/bin/env bash
# tests/test_context_cli.sh -- `aphotic context` and `aphotic runtime`
# against a fake `qs` that records its arguments and answers like the
# shell's IPC targets would.
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

source "$ROOT/Configs/.local/lib/aphotic/commands/cmd_context.sh"
source "$ROOT/Configs/.local/lib/aphotic/commands/cmd_runtime.sh"

export QS_CALL_LOG="$WORKDIR/qs_calls.log"
mkdir -p "$WORKDIR/bin"
cat > "$WORKDIR/bin/qs" <<'QS'
#!/usr/bin/env bash
echo "$*" >> "$QS_CALL_LOG"
[[ -n "${QS_FAIL:-}" ]] && exit 1
case "$*" in
    *"call context set focus") echo "focus" ;;
    *"call context set nope") echo "unknown context 'nope'" ;;
    *"call context current") echo "default" ;;
    *"call context list") printf '* default\tEverything\n  focus\tCalm\n' ;;
    *"call context revert") echo "default" ;;
    *"call aphotic back") echo "launcher" ;;
    *"call aphotic runtime") cat <<'JSON'
{"focusedScreen":"DP-1","screens":[{"screen":"DP-1","stack":["workspace","launcher"],"focusOwner":"launcher","mode":"primary","blocking":""}],
 "context":{"current":"game","previous":"default","policy":{}},
 "resources":{"level":"contention","surfaced":true,"headline":"GPU VRAM contended · ollama, gaming","resource":null,"negotiation":null,
   "history":[{"decision":"keep","label":"GPU VRAM","requestor":"gaming","claimant":"ollama"}],"dormant":false},
 "render":{"decorative":false,"covered":true},
 "activity":{"active":1,"idle":1,"wakeupsPerMinute":30,"probes":[
   {"name":"system.base","kind":"file","instances":1,"active":1,"interval":2000,"wakeupsPerMinute":30},
   {"name":"weather","kind":"network","instances":1,"active":0,"interval":1200000,"wakeupsPerMinute":0}]},
 "plugins":{"enabled":["pets"],"safeMode":false}}
JSON
    ;;
esac
exit 0
QS
chmod +x "$WORKDIR/bin/qs"
export PATH="$WORKDIR/bin:$PATH"

reset_logs() { : > "$OK_LOG"; : > "$ERR_LOG"; rm -f "$QS_CALL_LOG"; }

# set -> IPC set, reports the context the shell answered with.
reset_logs
aphotic_cmd_context set focus || fail "set focus exited nonzero"
grep -q -- "-c aphotic ipc call context set focus" "$QS_CALL_LOG" || fail "set did not call the context target: $(cat "$QS_CALL_LOG")"
grep -q "context set to 'focus'" "$OK_LOG" || fail "set did not report success"

# Unknown context: the shell refuses, the CLI fails loudly.
reset_logs
rc=0; aphotic_cmd_context set nope || rc=$?
[[ "$rc" -ne 0 ]] || fail "unknown context should exit nonzero"
grep -q "unknown context 'nope'" "$ERR_LOG" || fail "expected the shell's refusal on stderr"

# Malformed names never reach the shell.
reset_logs
rc=0; aphotic_cmd_context set 'Bad Name;rm' || rc=$?
[[ "$rc" -ne 0 ]] || fail "malformed name should exit nonzero"
[[ -f "$QS_CALL_LOG" ]] && fail "malformed name must not invoke qs"

# Missing name: usage, no IPC.
reset_logs
rc=0; aphotic_cmd_context set || rc=$?
[[ "$rc" -ne 0 ]] || fail "missing name should exit nonzero"
[[ -f "$QS_CALL_LOG" ]] && fail "missing name must not invoke qs"

# No subcommand prints the current context.
reset_logs
out="$(aphotic_cmd_context)"
[[ "$out" == "default" ]] || fail "bare context should print current, got '$out'"

# list and revert.
reset_logs
aphotic_cmd_context list | grep -q '^\* default' || fail "list should star the active context"
reset_logs
aphotic_cmd_context revert || fail "revert exited nonzero"
grep -q "reverted to 'default'" "$OK_LOG" || fail "revert did not report"

# Shell not running: a clear error, nonzero.
reset_logs
rc=0; QS_FAIL=1 aphotic_cmd_context current || rc=$?
[[ "$rc" -ne 0 ]] || fail "unreachable shell should exit nonzero"
grep -q "is 'qs -c aphotic' running" "$ERR_LOG" || fail "expected the unreachable-shell error"

# runtime summary renders only what the shell reported.
reset_logs
out="$(aphotic_cmd_runtime)" || fail "runtime exited nonzero"
grep -q "^APHOTIC RUNTIME" <<<"$out" || fail "summary header missing"
grep -q "Context        game" <<<"$out" || fail "context line missing: $out"
grep -q "CONTENTION  GPU VRAM contended" <<<"$out" || fail "resource line missing: $out"
grep -q "Motion         gated" <<<"$out" || fail "motion line missing"
grep -q "^\* DP-1 .*owner=launcher .*open=workspace, launcher" <<<"$out" || fail "screen line missing: $out"
grep -q "keep .*GPU VRAM: gaming vs ollama" <<<"$out" || fail "history line missing: $out"

grep -q "^Activity  1 active, 1 idle, ~30 scheduled wakeups/min" <<<"$out" || fail "activity header missing: $out"
grep -q "system.base .*file .*ACTIVE .*every 2s" <<<"$out" || fail "active probe row missing: $out"
grep -q "weather .*network .*idle .*every 1200s" <<<"$out" || fail "idle probe row missing: $out"
grep -q "^Plugins        pets" <<<"$out" || fail "plugins line missing: $out"

# --json passes the shell's JSON through untouched.
reset_logs
aphotic_cmd_runtime --json | python3 -c 'import json,sys; json.load(sys.stdin)' || fail "--json is not JSON"

# back reports what was closed.
reset_logs
aphotic_cmd_runtime back || fail "back exited nonzero"
grep -q "closed launcher" "$OK_LOG" || fail "back did not report the closed surface"

echo "PASS: context and runtime CLI"
