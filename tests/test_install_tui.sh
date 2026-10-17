#!/usr/bin/env bash
# tests/test_install_tui.sh
#
# install-tui.sh: the keyboard installer over install.sh. Covers the argv
# built for every exposed flag, the non-interactive/NO_COLOR fallback, and
# that nothing with a side effect runs before the Run screen. install.sh
# itself stays untouched; its flag-driven path is asserted unchanged at the
# end.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/bin" "$WORKDIR/home" "$WORKDIR/state" "$WORKDIR/backups"

# Answers come from a file: the menus read stdin directly (no command
# substitutions around them), so the read position is shared across screens.
answers() { printf '%b' "$1" > "$WORKDIR/answers"; }

# A stub install.sh records the argv it was called with and prints output for
# the log pane. The wrapper must call it, never the real installer.
cat > "$WORKDIR/install-stub.sh" <<EOF
#!/usr/bin/env bash
printf '%s' "\$*" > "$WORKDIR/argv"
touch "$WORKDIR/stub-ran"
echo "stub stage output line 1"
echo "── [1/7] Preflight ──"
echo "stub stage output line 2"
echo "── [2/7] Configuration ──"
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

# A deterministic GPU: the fake lspci keeps the flow independent of the
# build host. FAKE_GPU picks the vendor the wrapper sees.
cat > "$WORKDIR/bin/lspci" <<'EOF'
#!/usr/bin/env bash
case "${FAKE_GPU:-intel}" in
  nvidia) printf '%s\n' '0000:01:00.0 "VGA compatible controller [0300]" "NVIDIA Corporation [10de]" "GA102 [1c82]"' ;;
  amd) printf '%s\n' '0000:0c:00.0 "VGA compatible controller [0300]" "Advanced Micro Devices, Inc. [AMD/ATI] [1002]" "Navi 22 [73df]"' ;;
  *) printf '%s\n' '0000:00:02.0 "VGA compatible controller [0300]" "Intel Corporation [8086]" "UHD Graphics [1234]"' ;;
esac
EOF
chmod +x "$WORKDIR/bin/lspci"

# HOME is thrown away, backups point at a temp dir, and TUI_NO_SUDO skips the
# real sudo -v. TUI_INSTALL_SH points at the stub.
run_tui() {
  PATH="$WORKDIR/bin:$PATH" \
  HOME="$WORKDIR/home" \
  XDG_STATE_HOME="$WORKDIR/state" \
  APHOTIC_BACKUP_ROOT="$WORKDIR/backups" \
  FAKE_GPU="${FAKE_GPU:-intel}" \
  TUI_NO_SUDO=1 TUI_INSTALL_SH="$WORKDIR/install-stub.sh" \
  TERM="${TUI_TEST_TERM:-dumb}" \
  bash "$ROOT/install-tui.sh" "$@" < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
}

reset_run() { rm -f "$WORKDIR/argv" "$WORKDIR/stub-ran" "$WORKDIR/sudo-called" "$WORKDIR/out"; }

cd "$WORKDIR"

# --- welcome renders headless and quits cleanly, running nothing
reset_run
answers '4\n'
run_tui
[[ -f "$WORKDIR/stub-ran" ]] && fail "quit must not run install.sh"
[[ -f "$WORKDIR/sudo-called" ]] && fail "quit must not invoke sudo"
[[ -f "$WORKDIR/install.log" ]] && fail "quit must not write install.log"
grep -q "Aphotic" "$WORKDIR/out" || fail "expected the wordmark, got: $(cat "$WORKDIR/out")"
grep -qi "dry run" "$WORKDIR/out" || fail "expected a dry-run item, got: $(cat "$WORKDIR/out")"
grep -q "System" "$WORKDIR/out" || fail "expected detected system facts"

# --- EOF (non-TTY, e.g. CI) exits 0 instead of looping forever
reset_run
: > "$WORKDIR/answers"
set +e
run_tui
status=$?
set -e
[[ "$status" -eq 0 ]] || fail "EOF on stdin must exit 0, got $status"
grep -q "Aphotic" "$WORKDIR/out" || fail "non-TTY run must still print the screen"
[[ -f "$WORKDIR/install.log" ]] && fail "EOF must not start the installer"

# --- NO_COLOR and a dumb terminal: plain numbered menu, no escape bytes
reset_run
printf '4\n' > "$WORKDIR/answers"
NO_COLOR=1 TUI_TEST_TERM=xterm-256color \
  PATH="$WORKDIR/bin:$PATH" HOME="$WORKDIR/home" XDG_STATE_HOME="$WORKDIR/state" \
  APHOTIC_BACKUP_ROOT="$WORKDIR/backups" FAKE_GPU=intel TUI_NO_SUDO=1 \
  TUI_INSTALL_SH="$WORKDIR/install-stub.sh" \
  bash "$ROOT/install-tui.sh" < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
if grep -q $'\e' "$WORKDIR/out"; then fail "NO_COLOR run emitted escape bytes"; fi
grep -q "1) Full install" "$WORKDIR/out" || fail "expected the numbered fallback"

# --- defaults: full profile, no layers, default theme, not a dry run
reset_run
answers '1\n1\n1\n\n\n2\n1\n1\ny\n\nr\n'
run_tui
[[ -f "$WORKDIR/stub-ran" ]] || fail "the install flow must reach install.sh"
argv="$(cat "$WORKDIR/argv")"
grep -q -- "--profile full" <<< "$argv" || fail "expected --profile full, got: $argv"
grep -q -- "--with" <<< "$argv" && fail "no layers means no --with flag, got: $argv"
grep -q -- "--theme tokyonight" <<< "$argv" || fail "expected the default theme, got: $argv"
grep -q -- "--dry-run" <<< "$argv" && fail "a full install must not dry-run, got: $argv"
grep -q -- "--no-assistant" <<< "$argv" || fail "expected --no-assistant, got: $argv"

# --- dry run (welcome choice 3) adds --dry-run and nothing else changes
reset_run
answers '3\n1\n1\n\n\n2\n1\n1\ny\n\nr\n'
run_tui
grep -q -- "--dry-run" "$WORKDIR/argv" || fail "dry-run choice must pass --dry-run, got: $(cat "$WORKDIR/argv")"

# --- the wrapper's own --dry-run forces a preview argv
reset_run
answers '1\n1\n1\n\n\n2\n1\n1\ny\n\nr\n'
run_tui --dry-run
grep -q -- "--dry-run" "$WORKDIR/argv" || fail "wrapper --dry-run must reach install.sh, got: $(cat "$WORKDIR/argv")"

# --- config-only: just --config-only (plus channel), no profile/layers/theme
reset_run
answers '2\n1\nr\n'
run_tui
argv="$(cat "$WORKDIR/argv")"
grep -q -- "--config-only" <<< "$argv" || fail "expected --config-only, got: $argv"
grep -q -- "--profile" <<< "$argv" && fail "config-only must not pass --profile, got: $argv"
grep -q -- "--theme" <<< "$argv" && fail "config-only must not pass --theme, got: $argv"

# --- keep conflicts
reset_run
answers '1\n1\n1\n\n\n2\n1\n3\ny\n\nr\n'
run_tui
grep -q -- "--keep-conflicts" "$WORKDIR/argv" || fail "expected --keep-conflicts, got: $(cat "$WORKDIR/argv")"

# --- no backup
reset_run
answers '1\n1\n1\n\n\n2\n1\n1\nn\nr\n'
run_tui
grep -q -- "--no-backup" "$WORKDIR/argv" || fail "expected --no-backup, got: $(cat "$WORKDIR/argv")"

# --- keep-backups count when it is not the default
reset_run
answers '1\n1\n1\n\n\n2\n1\n1\ny\n0\nr\n'
run_tui
grep -q -- "--keep-backups 0" "$WORKDIR/argv" || fail "expected --keep-backups 0, got: $(cat "$WORKDIR/argv")"

# --- kitchen sink on a machine with an NVIDIA GPU: every remaining flag at once
reset_run
export FAKE_GPU=nvidia
answers '3\n2\n2\n2,4\n2\n1\n2\n2\n2\ny\n3\ny\nr\n'
run_tui
unset FAKE_GPU
argv="$(cat "$WORKDIR/argv")"
grep -q -- "--channel edge" <<< "$argv" || fail "expected --channel edge, got: $argv"
grep -q -- "--profile minimal" <<< "$argv" || fail "expected --profile minimal, got: $argv"
grep -q -- "--with dev,exploit-network,ai" <<< "$argv" || fail "expected the layer csv with ai added, got: $argv"
grep -q -- "--theme hackthebox" <<< "$argv" || fail "expected --theme hackthebox, got: $argv"
grep -q -- "--with-assistant" <<< "$argv" || fail "expected --with-assistant, got: $argv"
grep -q -- "--keep-sddm" <<< "$argv" || fail "expected --keep-sddm, got: $argv"
grep -q -- "--nvidia-driver reinstall" <<< "$argv" || fail "expected --nvidia-driver reinstall, got: $argv"
grep -q -- "--strip-conflicts" <<< "$argv" || fail "expected --strip-conflicts, got: $argv"
grep -q -- "--keep-backups 3" <<< "$argv" || fail "expected --keep-backups 3, got: $argv"
grep -q -- "--accept-exploit-disclaimer" <<< "$argv" || fail "expected --accept-exploit-disclaimer, got: $argv"
grep -q -- "--dry-run" <<< "$argv" || fail "expected --dry-run, got: $argv"

# --- back navigation returns to the previous screen
reset_run
answers '1\nb\n4\n'
run_tui
[[ "$(grep -c "What would you like to do?" "$WORKDIR/out")" -ge 2 ]] || fail "b should return to Welcome"

# --- the key reader: a lone ESC is back (never quit), and an arrow split
# across two reads still reads as an arrow
read_key() {
  bash -c 'source "$0/lib/install/tui/menu.sh"; tui_read_key; printf "%s" "$TUI_KEY"' "$ROOT"
}
key_one=$(printf '\e[A' | read_key)
[[ "$key_one" == "up" ]] || fail "one-chunk arrow should read as up, got: $key_one"
key_split=$( { printf '\e'; sleep 0.1; printf '[A'; } | read_key )
[[ "$key_split" == "up" ]] || fail "split arrow should read as up, got: $key_split"
key_esc=$(printf '\e' | read_key)
[[ "$key_esc" == "back" ]] || fail "a lone ESC must be back, not quit, got: $key_esc"

# --- the run screen reads stage constants from install.sh, never a copy
grep -q "^STAGE_COLORS=(" "$ROOT/install-tui.sh" && fail "wrapper must not hardcode STAGE_COLORS"
grep -rq "^STAGE_COLORS=(" "$ROOT/lib/install/tui/" && fail "lib must not hardcode STAGE_COLORS"
grep -q "^TOTAL_STAGES=" "$ROOT/install.sh" || fail "could not read TOTAL_STAGES from install.sh"

# --- log pane: seeded log plus stub output, tail window only
reset_run
for i in $(seq 1 20); do echo "seed-$i" >> "$WORKDIR/install.log"; done
answers '1\n1\n1\n\n\n2\n1\n1\ny\n\nr\n'
TUI_LOG_LINES=10 PATH="$WORKDIR/bin:$PATH" HOME="$WORKDIR/home" XDG_STATE_HOME="$WORKDIR/state" \
  APHOTIC_BACKUP_ROOT="$WORKDIR/backups" FAKE_GPU=intel TUI_NO_SUDO=1 \
  TUI_INSTALL_SH="$WORKDIR/install-stub.sh" TERM=dumb \
  bash "$ROOT/install-tui.sh" < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
grep -q "seed-20" "$WORKDIR/out" || fail "expected the tail window to show recent log lines"
grep -q "stub stage output line 2" "$WORKDIR/out" || fail "expected stub output in the log pane"
grep -q "seed-1$" "$WORKDIR/out" && fail "tail window must not show the whole log"
grep -q "seed-1" "$WORKDIR/install.log" || fail "wrapper must not truncate install.log"

# --- passwords never reach the log
reset_run
answers '1\n1\n1\n\n\n2\n1\n1\ny\n\nr\ns3cret-pw-xyz\n'
run_tui
grep -q "s3cret-pw-xyz" "$WORKDIR/install.log" && fail "typed input must never be written to install.log"
grep -q "s3cret-pw-xyz" "$WORKDIR/out" && fail "typed input must never be echoed back"

# --- at the 80-column minimum no line spills, across every screen
reset_run
export FAKE_GPU=nvidia
answers '1\n1\n1\n2,4\n\n2\n1\n1\n1\ny\n\ny\nr\n'
COLUMNS=80 LINES=24 PATH="$WORKDIR/bin:$PATH" HOME="$WORKDIR/home" XDG_STATE_HOME="$WORKDIR/state" \
  APHOTIC_BACKUP_ROOT="$WORKDIR/backups" FAKE_GPU=nvidia TUI_NO_SUDO=1 \
  TUI_INSTALL_SH="$WORKDIR/install-stub.sh" TERM=dumb \
  bash "$ROOT/install-tui.sh" < "$WORKDIR/answers" > "$WORKDIR/out" 2>&1
unset FAKE_GPU
python3 - "$WORKDIR/out" 80 <<'PY' || fail "a screen line exceeded 80 columns at the 80x24 minimum"
import sys, re, unicodedata
path, limit = sys.argv[1], int(sys.argv[2])
ansi = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')
def width(s):
    return sum(2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1 for c in s)
bad = []
for i, raw in enumerate(open(path, encoding='utf-8', errors='replace'), 1):
    line = ansi.sub('', raw.rstrip('\n')).replace('\r', '')
    if width(line) > limit:
        bad.append((i, width(line), line))
if bad:
    for i, w, line in bad[:8]:
        print(f"line {i}: width {w}: {line}")
    sys.exit(1)
PY

# --- install.sh keeps its flag-driven path: the wrapper changed nothing
cd "$ROOT"
output=$(bash install.sh --dry-run --profile full --theme default < /dev/null 2>&1)
echo "$output" | grep -q "profile: full" || fail "install.sh flag path changed: $output"

echo "PASS: installer TUI (screens, argv per flag, plain fallback, no side effects before Run, log pane, no password leak)"