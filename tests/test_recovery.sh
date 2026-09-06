#!/usr/bin/env bash
# tests/test_recovery.sh
#
# REL-01. The recovery path only earns its place if it works with no
# shell running, so everything here drives the bash side directly with a
# fake HOME and no quickshell anywhere.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

export HOME="$WORKDIR/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_RUNTIME_DIR="$WORKDIR/run"
export APHOTIC_DOTS_DIR="$ROOT"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"

LIB_DIR="$ROOT/Configs/.local/lib/aphotic"
COMMANDS_DIR="$LIB_DIR/commands"
export LIB_DIR COMMANDS_DIR

# shellcheck source=/dev/null
source "$LIB_DIR/globalcontrol.sh"

# Nothing in this test may reach the real systemd, the real journal or
# the real shell -- a stubbed PATH is what keeps `apply` from restarting
# anything on the machine running the tests.
mkdir -p "$WORKDIR/bin"
export CALL_LOG="$WORKDIR/calls.log"
for stub in systemctl journalctl qs hyprctl; do
    cat > "$WORKDIR/bin/$stub" <<EOF
#!/usr/bin/env bash
echo "$stub \$*" >> "\$CALL_LOG"
exit 0
EOF
    chmod +x "$WORKDIR/bin/$stub"
done
export PATH="$WORKDIR/bin:$PATH"

source "$COMMANDS_DIR/cmd_recovery.sh"

# --- 1. a clean stop is not a failure --------------------------------
aphotic_cmd_recovery record success 0
[[ "$(_aphotic_recovery_failure_count)" == "0" ]] \
    || fail "a successful exit must not be recorded as a failure"

# --- 2. failed exits accumulate, bounded ------------------------------
for _ in $(seq 1 12); do
    aphotic_cmd_recovery record exit-code 1
done
count="$(_aphotic_recovery_failure_count)"
[[ "$count" == "$APHOTIC_RECOVERY_KEEP" ]] \
    || fail "expected the failure list capped at $APHOTIC_RECOVERY_KEEP, got $count"

# --- 3. a plugin named in the failure output is the suspect -----------
mkdir -p "$APHOTIC_PLUGINS_DIR/agent-graph" "$APHOTIC_PLUGINS_DIR/decoy"
for p in agent-graph decoy; do
    printf '[plugin]\nname = "%s"\nversion = "1.0.0"\n' "$p" > "$APHOTIC_PLUGINS_DIR/$p/plugin.toml"
done
cat > "$APHOTIC_STATE_HOME/shell.log" <<EOF
file://$APHOTIC_PLUGINS_DIR/decoy/qml/Decoy.qml:1 loaded fine
QQmlApplicationEngine failed to load component
file://$APHOTIC_PLUGINS_DIR/agent-graph/qml/AgentGraphTab.qml:41 Type error
EOF
# journalctl is stubbed to print nothing, so the log file is the source.
suspect="$(_aphotic_recovery_suspect_plugin || true)"
[[ "$suspect" == "agent-graph" ]] \
    || fail "expected agent-graph as the suspect (last plugin path in the output), got '${suspect:-none}'"

# --- 4. a path that is not an installed plugin is never a suspect -----
# The whole point of asking "does the output mention this installed
# plugin" rather than "does this look like a plugin path".
cat > "$APHOTIC_STATE_HOME/shell.log" <<EOF
file://$APHOTIC_PLUGINS_DIR/never-installed/qml/Thing.qml:3 Type error
EOF
suspect="$(_aphotic_recovery_suspect_plugin || true)"
[[ -z "$suspect" ]] \
    || fail "a plugin directory that does not exist must not be named as a suspect, got '$suspect'"

# --- 5. status --json is parseable and carries the diagnosis ----------
cat > "$APHOTIC_STATE_HOME/shell.log" <<EOF
file://$APHOTIC_PLUGINS_DIR/agent-graph/qml/AgentGraphTab.qml:41 Type error
EOF
aphotic_record_change "plugin-registered" "agent-graph 1.2.0"
json="$(aphotic_cmd_recovery status --json)"
echo "$json" | jq -e . >/dev/null 2>&1 || fail "status --json did not emit valid JSON"
[[ "$(echo "$json" | jq -r .suspectPlugin)" == "agent-graph" ]] \
    || fail "status --json did not carry the suspected plugin"
[[ "$(echo "$json" | jq -r .safeMode)" == "false" ]] \
    || fail "status --json reported safe mode on when it is off"
echo "$json" | jq -r .lastChange | grep -q "agent-graph 1.2.0" \
    || fail "status --json did not carry the last recorded change"

# --- 6. safe mode round-trips through the file the shell watches ------
source "$COMMANDS_DIR/cmd_safemode.sh"
aphotic_safe_mode_active && fail "safe mode must start off"
aphotic_safe_mode_set true "test" || fail "could not turn safe mode on"
aphotic_safe_mode_active || fail "safe mode did not read back as on"
[[ "$(aphotic_safe_mode_reason)" == "test" ]] || fail "safe mode reason did not round-trip"
[[ "$(jq -r .active "$APHOTIC_SAFE_MODE_FILE")" == "true" ]] \
    || fail "safe-mode.json is not the shape services/SafeMode.qml parses"
aphotic_safe_mode_set false "" || fail "could not turn safe mode off"
aphotic_safe_mode_active && fail "safe mode did not read back as off"

# --- 7. apply safe-mode sets the flag, clears failures, restarts ------
: > "$CALL_LOG"
aphotic_cmd_recovery apply safe-mode >/dev/null 2>&1 || fail "apply safe-mode failed"
aphotic_safe_mode_active || fail "apply safe-mode did not turn safe mode on"
[[ "$(_aphotic_recovery_failure_count)" == "0" ]] \
    || fail "apply must clear the recorded failures once it has acted"
grep -q "systemctl .*reset-failed aphotic-shell.service" "$CALL_LOG" \
    || fail "apply must clear the systemd start limit, or the restart is refused"
grep -q "systemctl .*restart aphotic-shell.service" "$CALL_LOG" \
    || fail "apply must restart the shell"

# --- 8. apply disable-suspect refuses when nothing is suspected -------
rm -f "$APHOTIC_STATE_HOME/shell.log"
: > "$CALL_LOG"
rc=0
aphotic_cmd_recovery apply disable-suspect >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "disable-suspect must refuse when no plugin is suspected"
grep -q "systemctl" "$CALL_LOG" && fail "a refused action must not touch the shell unit"

# --- 9. an unknown action is refused, not guessed at ------------------
rc=0
aphotic_cmd_recovery apply demolish >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "an unknown recovery action must fail"

echo "PASS: recovery record/suspect/status + safe mode round-trip + apply"
