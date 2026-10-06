#!/usr/bin/env bash
# tests/test_agent_run_cmd.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

export HOME="$WORKDIR/home"
export APHOTIC_STATE_HOME="$WORKDIR/state"
mkdir -p "$HOME" "$APHOTIC_STATE_HOME"

aphotic_require() { command -v "$1" >/dev/null 2>&1; }
aphotic_log() { :; }
export -f aphotic_require aphotic_log

source "$ROOT/Configs/.local/lib/aphotic/commands/cmd_agent.sh"

EVENTS="$APHOTIC_STATE_HOME/agent-events.jsonl"

field() { # field <line-number> <json-key>
    sed -n "${1}p" "$EVENTS" | python3 -c "import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ''))" "$2"
}

# --- run wraps a command: start, active turn, end -- in that order, one session

aphotic_cmd_agent run --harness myagent -- bash -c 'true'

[[ "$(wc -l < "$EVENTS")" -eq 3 ]] || fail "expected 3 events, got $(wc -l < "$EVENTS")"
[[ "$(field 1 event)" == "session_start" ]] || fail "first event is not session_start: $(sed -n 1p "$EVENTS")"
[[ "$(field 1 status)" == "running" ]] || fail "session_start not running"
[[ "$(field 1 harness)" == "myagent" ]] || fail "session_start missing harness"
[[ -n "$(field 1 cwd)" ]] || fail "session_start missing cwd"
[[ "$(field 2 event)" == "turn" ]] || fail "second event is not turn: $(sed -n 2p "$EVENTS")"
[[ "$(field 2 status)" == "running" ]] || fail "turn not running"
[[ "$(field 3 event)" == "session_end" ]] || fail "third event is not session_end: $(sed -n 3p "$EVENTS")"
[[ "$(field 3 status)" == "ended" ]] || fail "session_end not ended"
[[ "$(field 3 endReason)" == "exited" ]] || fail "session_end missing endReason"

sid1="$(field 1 sessionId)"
sid2="$(field 3 sessionId)"
[[ "$sid1" == "$sid2" ]] || fail "events split across two sessions: $sid1 / $sid2"
[[ "$sid1" == run-* ]] || fail "session id not in run- form: $sid1"
[[ ! -f "$APHOTIC_STATE_HOME/agent-sessions/$sid1.json" ]] || fail "session file not removed on end"
[[ -f "$APHOTIC_STATE_HOME/agent-runs/$sid1.jsonl" ]] || fail "run archive missing"

# --- the wrapped command's exit code comes back unchanged

set +e
aphotic_cmd_agent run --harness myagent -- bash -c 'exit 7'
rc=$?
set -e
[[ "$rc" -eq 7 ]] || fail "expected exit 7 from wrapped command, got $rc"

# a failed command still gets its session_end
last=$(tail -n 1 "$EVENTS")
[[ "$(echo "$last" | python3 -c 'import json,sys; print(json.load(sys.stdin)["event"])')" == "session_end" ]] \
    || fail "failed command did not write session_end: $last"

# --- argument handling

set +e
aphotic_cmd_agent run -- bash -c 'true' >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "run without --harness should fail"

set +e
aphotic_cmd_agent run --harness myagent >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "run without a command after -- should fail"

set +e
aphotic_cmd_agent run --harness myagent --not-a-flag >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "run with an unexpected argument should fail"

# --- emit through the CLI

before=$(wc -l < "$EVENTS")
aphotic_cmd_agent emit usage --session s-cli --harness myagent --model qwen3.8 --tokens-in 42 --tokens-out 7
line=$(sed -n "$((before + 1))p" "$EVENTS")
[[ "$(echo "$line" | python3 -c 'import json,sys; print(json.load(sys.stdin)["inputTokens"])')" == "42" ]] \
    || fail "emit did not write the token count: $line"
[[ "$(echo "$line" | python3 -c 'import json,sys; print(json.load(sys.stdin)["harness"])')" == "myagent" ]] \
    || fail "emit record missing harness: $line"

set +e
aphotic_cmd_agent emit bogus --session s-cli --harness myagent >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "emit with an unknown event kind should fail"

echo "PASS: agent run frames a command as a session; exit codes and argument errors intact; emit writes v2 records"
