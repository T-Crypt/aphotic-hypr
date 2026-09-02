#!/usr/bin/env bash
# tests/test_config_sync_orphan_kill.sh
# Reproduces the live bug (--config-only leaving a duplicate `qs -c
# aphotic` process running): `systemctl --user restart` only manages
# whatever's already in the unit's own cgroup, so a process that predates
# the service's current Main PID survives a restart untouched and
# duplicates the bar. kill_orphan_qs_processes (lib/install/
# config_deploy.sh) must kill exactly that PID and leave the current
# Main PID alone.
#
# It must also take the orphan's own children with it. Quickshell does not
# reap its Process children on SIGTERM, so `nmcli monitor`, `dbus-monitor`
# and the agent-events `tail`s reparent to init -- one fresh set per run,
# 121 of them holding 1.0 GiB measured on a real machine.
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

# Argument-aware, unlike a single canned list: `-f <pattern>` enumerates
# daemons, `-P <pid>` enumerates that PID's children. Conflating the two
# is how a stub can make a child reap look like a runaway kill.
write_pgrep() {
    cat > "$WORKDIR/bin/pgrep" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "-P" ]]; then
    case "\$2" in
        11111) printf '9001\n9002\n' ;;   # nmcli monitor, dbus-monitor
        *) : ;;
    esac
    exit 0
fi
printf '%s\n' $1
EOF
    chmod +x "$WORKDIR/bin/pgrep"
}

# Not a group leader: pgid differs from the pid, so the group is not ours
# to signal and the children must be collected explicitly.
write_ps_follower() {
    cat > "$WORKDIR/bin/ps" <<'EOF'
#!/usr/bin/env bash
echo " 500"
EOF
    chmod +x "$WORKDIR/bin/ps"
}

write_pgrep "'11111' '42424' '33333'"
write_ps_follower

: > "$KILL_LOG"
kill_orphan_qs_processes

grep -qx -- "-TERM 11111" "$KILL_LOG" || fail "expected orphan PID 11111 to be killed, log: $(cat "$KILL_LOG")"
grep -qx -- "-TERM 33333" "$KILL_LOG" || fail "expected orphan PID 33333 to be killed, log: $(cat "$KILL_LOG")"
grep -q -- "42424" "$KILL_LOG" && fail "expected the service's own current Main PID (42424) NOT to be killed"
grep -qx -- "-TERM 9001 9002" "$KILL_LOG" \
    || fail "expected orphan 11111's children (9001 9002) to be reaped with it, log: $(cat "$KILL_LOG")"

# --- a group-leading orphan is taken down as a group, in one signal ---
write_ps_leader() {
    cat > "$WORKDIR/bin/ps" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in -p) shift; echo " $1"; exit 0 ;; esac
  shift
done
EOF
    chmod +x "$WORKDIR/bin/ps"
}
write_pgrep "'11111'"
write_ps_leader
: > "$KILL_LOG"
kill_orphan_qs_processes
grep -qx -- "-TERM -- -11111" "$KILL_LOG" \
    || fail "expected a group-leading orphan to be killed by process group, log: $(cat "$KILL_LOG")"
[[ "$(wc -l < "$KILL_LOG")" -eq 1 ]] \
    || fail "expected a group kill to be the only signal sent, got: $(cat "$KILL_LOG")"

# --- no orphans (pgrep reports only the service's own PID) -> no kills ---
write_pgrep "'42424'"
write_ps_follower
: > "$KILL_LOG"
kill_orphan_qs_processes
[[ -s "$KILL_LOG" ]] && fail "expected no kill calls when pgrep reports only the service's own PID, got: $(cat "$KILL_LOG")"

# --- service not running (MainPID empty/0) -> everything found is an orphan ---
cat > "$WORKDIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *"show"* ]] && echo "0"
EOF
write_pgrep "'55555'"
: > "$KILL_LOG"
kill_orphan_qs_processes
grep -qx -- "-TERM 55555" "$KILL_LOG" || fail "expected the lone stray PID to be killed when the service reports no Main PID, log: $(cat "$KILL_LOG")"

echo "PASS: kill_orphan_qs_processes kills only PIDs not owned by aphotic-shell.service, and reaps their children"
