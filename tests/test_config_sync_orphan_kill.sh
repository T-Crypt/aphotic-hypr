#!/usr/bin/env bash
# tests/test_config_sync_orphan_kill.sh
# Reproduces the live bug (--config-only leaving a duplicate `qs -c
# aphotic` process running): `systemctl --user restart` only manages
# whatever's already in the unit's own cgroup, so a process that predates
# the service's current Main PID survives a restart untouched and
# duplicates the bar. kill_orphan_qs_processes (lib/install/
# config_deploy.sh) must kill exactly that PID and leave the current
# Main PID alone.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

CWR="[WARNING]"
INSTLOG="$WORKDIR/install.log"
: > "$INSTLOG"

mkdir -p "$WORKDIR/bin"
export PATH="$WORKDIR/bin:$PATH"

KILL_LOG="$WORKDIR/killed.log"

# `kill` is a shell builtin -- a function of the same name shadows it in
# bash's lookup order (functions before regular builtins), so this is
# enough to intercept it without needing a PATH stub.
kill() { echo "$*" >> "$KILL_LOG"; }

source "$ROOT/lib/install/config_deploy.sh"

# --- fake systemctl reporting a known current Main PID ---
cat > "$WORKDIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"show"* ]]; then
    echo "42424"
fi
EOF
chmod +x "$WORKDIR/bin/systemctl"

# --- fake pgrep reporting the real service PID plus two orphans ---
cat > "$WORKDIR/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
printf '11111\n42424\n33333\n'
EOF
chmod +x "$WORKDIR/bin/pgrep"

: > "$KILL_LOG"
kill_orphan_qs_processes

grep -qx "11111" "$KILL_LOG" || fail "expected orphan PID 11111 to be killed, log: $(cat "$KILL_LOG")"
grep -qx "33333" "$KILL_LOG" || fail "expected orphan PID 33333 to be killed, log: $(cat "$KILL_LOG")"
grep -qx "42424" "$KILL_LOG" && fail "expected the service's own current Main PID (42424) NOT to be killed"
[[ "$(wc -l < "$KILL_LOG")" -eq 2 ]] || fail "expected exactly 2 kill calls (the two orphans only), got: $(cat "$KILL_LOG")"

# --- no orphans (pgrep reports only the service's own PID) -> no kills ---
cat > "$WORKDIR/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
printf '42424\n'
EOF
: > "$KILL_LOG"
kill_orphan_qs_processes
[[ -s "$KILL_LOG" ]] && fail "expected no kill calls when pgrep reports only the service's own PID, got: $(cat "$KILL_LOG")"

# --- service not running (MainPID empty/0) -> everything found is an orphan ---
cat > "$WORKDIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *"show"* ]] && echo "0"
EOF
cat > "$WORKDIR/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
printf '55555\n'
EOF
: > "$KILL_LOG"
kill_orphan_qs_processes
grep -qx "55555" "$KILL_LOG" || fail "expected the lone stray PID to be killed when the service reports no Main PID, log: $(cat "$KILL_LOG")"

echo "PASS: kill_orphan_qs_processes kills only PIDs not owned by aphotic-shell.service's current Main PID"
