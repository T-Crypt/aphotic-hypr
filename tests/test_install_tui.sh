#!/usr/bin/env bash
# tests/test_install_tui.sh
#
# The install-tui.sh wrapper (menu-driven UI over install.sh): the menu
# renders and quits cleanly headless, picked answers map to the exact
# install.sh argv, stage constants are read from install.sh rather than
# copied, the log pane tails install.log, and no password ever lands in
# the log. install.sh itself stays untouched (flag-driven CI path intact).
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# Answers come from a file, not a pipe: the pickers run in command
# substitutions and only a seekable fd keeps the read position shared.
answers() { printf '%b' "$1" > "$WORKDIR/answers"; }

# A stub install.sh records the argv it was called with and emits output
# for the log pane. The wrapper must call it, never the real installer.
mkdir -p "$WORKDIR/bin"
cat > "$WORKDIR/install-stub.sh" <<EOF
#!/usr/bin/env bash
printf '%s' "\$*" > "$WORKDIR/argv"
echo "stub stage output line 1"
echo "stub stage output line 2"
touch "$WORKDIR/stub-ran"
EOF
chmod +x "$WORKDIR/install-stub.sh"

# Any accidental sudo call fails the run loudly.
cat > "$WORKDIR/bin/sudo" <<EOF
#!/usr/bin/env bash
touch "$WORKDIR/sudo-called"
echo "unexpected sudo call: \$*" >&2
exit 1
EOF
chmod +x "$WORKDIR/bin/sudo"

# The wrapper under test. TUI_NO_SUDO skips the real `sudo -v` even on a
# TTY; TUI_INSTALL_SH points at the stub; PATH shadow catches leaks.
run_tui() {
  PATH="$WORKDIR/bin:$PATH" TUI_NO_SUDO=1 TUI_INSTALL_SH="$WORKDIR/install-stub.sh" \
    bash "$ROOT/install-tui.sh" "$@" < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
}

cd "$WORKDIR"

# --- menu renders headless and quits cleanly, running nothing
answers '4\n'
run_tui
[[ -f "$WORKDIR/stub-ran" ]] && fail "quit must not run install.sh"
[[ -f "$WORKDIR/sudo-called" ]] && fail "quit must not invoke sudo"
[[ -f "$WORKDIR/install.log" ]] && fail "quit must not write install.log"
grep -q "APHOTIC" "$WORKDIR/out" || fail "expected the banner, got: $(cat "$WORKDIR/out")"
grep -qi "dry-run" "$WORKDIR/out" || fail "expected a dry-run menu item, got: $(cat "$WORKDIR/out")"

# --- EOF (non-TTY, e.g. CI) exits 0 instead of looping forever
: > "$WORKDIR/answers"
set +e
PATH="$WORKDIR/bin:$PATH" TUI_NO_SUDO=1 TUI_INSTALL_SH="$WORKDIR/install-stub.sh" \
  bash "$ROOT/install-tui.sh" < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
status=$?
set -e
[[ "$status" -eq 0 ]] || fail "EOF on stdin must exit 0, got $status"
grep -q "APHOTIC" "$WORKDIR/out" || fail "non-TTY run must still print the options"

# --- flag mapping: Install with full profile, no extras, default theme
rm -f "$WORKDIR/argv" "$WORKDIR/stub-ran"
answers '1\n1\n2\n\n'
run_tui
[[ -f "$WORKDIR/stub-ran" ]] || fail "choice 1 must run install.sh"
grep -q -- "--profile full" "$WORKDIR/argv" || fail "expected --profile full, got: $(cat "$WORKDIR/argv")"
grep -q -- "--with" "$WORKDIR/argv" && fail "no extras means no --with flag, got: $(cat "$WORKDIR/argv")"
grep -q -- "--theme" "$WORKDIR/argv" || fail "expected a --theme flag, got: $(cat "$WORKDIR/argv")"
grep -q -- "--dry-run" "$WORKDIR/argv" && fail "choice 1 must not dry-run, got: $(cat "$WORKDIR/argv")"

# --- flag mapping: Dry-run preview adds --dry-run
rm -f "$WORKDIR/argv" "$WORKDIR/stub-ran"
answers '2\n1\n2\n\n'
run_tui
[[ -f "$WORKDIR/stub-ran" ]] || fail "choice 2 must run install.sh"
grep -q -- "--dry-run" "$WORKDIR/argv" || fail "expected --dry-run, got: $(cat "$WORKDIR/argv")"
grep -q -- "--profile full" "$WORKDIR/argv" || fail "expected --profile full, got: $(cat "$WORKDIR/argv")"

# --- the wrapper's own --dry-run flag forces a preview argv
rm -f "$WORKDIR/argv" "$WORKDIR/stub-ran"
answers '1\n1\n2\n\n'
run_tui --dry-run
grep -q -- "--dry-run" "$WORKDIR/argv" || fail "wrapper --dry-run must reach install.sh, got: $(cat "$WORKDIR/argv")"

# --- Guided answers runs install.sh with no collected flags of its own
rm -f "$WORKDIR/argv" "$WORKDIR/stub-ran"
answers '3\n'
run_tui
[[ -f "$WORKDIR/stub-ran" ]] || fail "choice 3 must hand off to install.sh"
[[ -s "$WORKDIR/argv" ]] && fail "choice 3 passes no picker flags, got: $(cat "$WORKDIR/argv")"

# --- Guided answers keeps the wrapper --dry-run flag (regression)
rm -f "$WORKDIR/argv" "$WORKDIR/stub-ran"
answers '3\n'
run_tui --dry-run
[[ -f "$WORKDIR/stub-ran" ]] || fail "choice 3 with --dry-run must run install.sh"
grep -q -- "--dry-run" "$WORKDIR/argv" || fail "choice 3 must keep wrapper --dry-run, got: $(cat "$WORKDIR/argv")"

# --- stage constants come from install.sh, never a copy in the wrapper
grep -q "^STAGE_COLORS=(" "$ROOT/install-tui.sh" && fail "wrapper must not hardcode STAGE_COLORS"
total="$(sed -n 's/^TOTAL_STAGES=//p' "$ROOT/install.sh")"
[[ -n "$total" ]] || fail "could not read TOTAL_STAGES from install.sh"
answers '4\n'
run_tui
grep -q "($total stages)" "$WORKDIR/out" || fail "expected the wrapper to report $total stages, got: $(cat "$WORKDIR/out")"

# --- log pane: seeded log plus stub output, tail window only
rm -f "$WORKDIR/stub-ran"
for i in $(seq 1 20); do echo "seed-$i" >> "$WORKDIR/install.log"; done
answers '1\n1\n2\n\n'
TUI_LOG_LINES=10 PATH="$WORKDIR/bin:$PATH" TUI_NO_SUDO=1 TUI_INSTALL_SH="$WORKDIR/install-stub.sh" \
  bash "$ROOT/install-tui.sh" < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
grep -q "seed-20" "$WORKDIR/out" || fail "expected the tail window to show recent log lines"
grep -q "stub stage output line 2" "$WORKDIR/out" || fail "expected stub output in the log pane"
grep -q "seed-1$" "$WORKDIR/out" && fail "tail window must not show the whole log"
grep -q "seed-1" "$WORKDIR/install.log" || fail "wrapper must not truncate install.log"

# --- passwords never reach the log
rm -f "$WORKDIR/install.log" "$WORKDIR/stub-ran"
answers '1\n1\n2\n\ns3cret-pw-xyz\n'
run_tui
grep -q "s3cret-pw-xyz" "$WORKDIR/install.log" && fail "typed input must never be written to install.log"
grep -q "s3cret-pw-xyz" "$WORKDIR/out" && fail "typed input must never be echoed back"

# --- install.sh keeps its flag-driven path: the wrapper changed nothing
cd "$ROOT"
output=$(bash install.sh --dry-run --profile full --theme default < /dev/null 2>&1)
echo "$output" | grep -q "profile: full" || fail "install.sh flag path changed: $output"

echo "PASS: installer TUI wrapper (menu, flags, stages, log pane, no sudo, no password leak)"
