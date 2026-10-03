#!/usr/bin/env bash
# tests/test_uninstall.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

export HOME="$WORKDIR/home"
export APHOTIC_BACKUP_ROOT="$WORKDIR/backups"

# uninstall.sh runs `systemctl --user disable --now aphotic-shell.service`
# and, for the greeter scaffold, `sudo rm -rf` under /etc. Neither reads
# HOME: `systemctl --user` talks to the session's user manager over
# $XDG_RUNTIME_DIR, so sandboxing HOME above does nothing to contain it.
# Running this test on a machine with Aphotic installed used to stop the
# developer's live shell and unlink its unit, since `disable` removes a
# symlinked unit outright. Stub both onto PATH and log the calls, so the
# assertions below can check uninstall still asked for the right things.
export STUB_LOG="$WORKDIR/stub-calls.log"
# Point the greeter probe at an empty tree for these two cases. Left unset it
# defaults to the real /etc, so on a machine with the greeter installed the
# branch below ran and "removal must not happen" turned into a false failure.
# The greeter is covered on its own, further down, against a seeded tree.
export GREETER_PROBE_DIR="$WORKDIR/etc-absent"
mkdir -p "$GREETER_PROBE_DIR"
mkdir -p "$WORKDIR/bin"
cat > "$WORKDIR/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB_LOG"
# greetd is not part of this test; report it absent so uninstall skips the
# greeter branch instead of prompting for a scaffold that is not here.
case "$*" in
  *is-enabled*|*is-active*) exit 1 ;;
esac
exit 0
STUB
cat > "$WORKDIR/bin/sudo" <<'STUB'
#!/usr/bin/env bash
echo "sudo $*" >> "$STUB_LOG"
exit 0
STUB
chmod +x "$WORKDIR/bin/systemctl" "$WORKDIR/bin/sudo"
export PATH="$WORKDIR/bin:$PATH"
mkdir -p "$HOME/.config/waybar" "$APHOTIC_BACKUP_ROOT/20260101-000000/waybar"
echo "backed-up" > "$APHOTIC_BACKUP_ROOT/20260101-000000/waybar/config.jsonc"
echo "current" > "$HOME/.config/waybar/config.jsonc"

cat > "$WORKDIR/aphotic.toml" <<'EOF'
[install]
profile = "full"
layers = []
installed_at = "2026-08-18T10:00:00"

[theme]
name = "default"

[bar]
position = "top"

[system]
nvidia = false
aur_helper = "yay"
EOF

cd "$ROOT"
# --yes, not `echo y`. This box has the greeter installed, so uninstall.sh
# asks about the scaffold as well as the backup, and piping one answer in
# left `read` at EOF on the second prompt with set -e live. That made this
# test fail on any machine with Aphotic installed and pass in CI, whose
# runner has neither the greeter nor the packages.
bash uninstall.sh --yes --aphotic-toml "$WORKDIR/aphotic.toml" < /dev/null

content=$(cat "$HOME/.config/waybar/config.jsonc")
[[ "$content" == "backed-up" ]] || fail "expected backup restored, got '$content'"

echo "PASS: uninstall restores latest backup"

grep -q -- "systemctl --user disable --now aphotic-shell.service" "$STUB_LOG" \
  || fail "expected uninstall to disable aphotic-shell.service, got: $(cat "$STUB_LOG")"
grep -q -- "sudo rm -rf /etc" "$STUB_LOG" \
  && fail "greeter scaffold removal must not run when greetd is absent, got: $(cat "$STUB_LOG")"

echo "PASS: uninstall disables the shell unit through a stub, not the live session"

# --- Test: no backups present -> uninstall must fail loudly, not report success ---
WORKDIR2=$(mktemp -d)
trap 'rm -rf "$WORKDIR" "$WORKDIR2"' EXIT

export HOME="$WORKDIR2/home"
export APHOTIC_BACKUP_ROOT="$WORKDIR2/backups"
export STUB_LOG="$WORKDIR2/stub-calls.log"
mkdir -p "$HOME/.config"
# Intentionally do NOT create APHOTIC_BACKUP_ROOT — no backups exist at all.

cat > "$WORKDIR2/aphotic.toml" <<'EOF'
[install]
profile = "full"
layers = []
installed_at = "2026-08-18T10:00:00"

[theme]
name = "default"

[bar]
position = "top"

[system]
nvidia = false
aur_helper = "yay"
EOF

cd "$ROOT"
set +e
output=$(bash uninstall.sh --yes --aphotic-toml "$WORKDIR2/aphotic.toml" < /dev/null 2>&1)
status=$?
set -e

[[ "$status" -ne 0 ]] || fail "expected non-zero exit when no backups found, got $status"
[[ "$output" != *"Uninstall complete."* ]] || fail "expected no 'Uninstall complete.' message, got: $output"

echo "PASS: uninstall fails loudly when no backups exist"

# --- Test: the greeter branch, and that --yes cannot get past its guard ---
#
# This branch is gated on a scaffold file really existing under /etc, so on a
# CI runner it never ran. The developer's box has it, the prompt went in with
# the greeter in #130, and the single `echo "y"` this test used to pipe in ran
# out of answers mid-script: the test failed wherever Aphotic was installed
# and passed everywhere else. GREETER_PROBE_DIR points the check at a seeded
# tree instead, so both cases below run in CI.
WORKDIR3=$(mktemp -d)
trap 'rm -rf "$WORKDIR" "$WORKDIR2" "$WORKDIR3"' EXIT

export HOME="$WORKDIR3/home"
export APHOTIC_BACKUP_ROOT="$WORKDIR3/backups"
export STUB_LOG="$WORKDIR3/stub-calls.log"
export GREETER_PROBE_DIR="$WORKDIR3/etc"
mkdir -p "$HOME/.config/waybar" "$APHOTIC_BACKUP_ROOT/20260101-000000/waybar"
echo "backed-up" > "$APHOTIC_BACKUP_ROOT/20260101-000000/waybar/config.jsonc"
echo "current" > "$HOME/.config/waybar/config.jsonc"
mkdir -p "$GREETER_PROBE_DIR/xdg/quickshell/aphotic-greeter" "$GREETER_PROBE_DIR/greetd/aphotic"
echo "// greeter" > "$GREETER_PROBE_DIR/xdg/quickshell/aphotic-greeter/shell.qml"
echo "-- greetd" > "$GREETER_PROBE_DIR/greetd/aphotic/hyprland-greeter.lua"
cp "$WORKDIR/aphotic.toml" "$WORKDIR3/aphotic.toml"
mkdir -p "$WORKDIR3/bin"

# greetd reported absent: --yes removes the scaffold, and the removal targets
# the probed tree rather than the real /etc.
cat > "$WORKDIR3/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB_LOG"
case "$*" in
  *is-enabled*|*is-active*) exit 1 ;;
esac
exit 0
STUB
chmod +x "$WORKDIR3/bin/systemctl"
mkdir -p "$WORKDIR3/bin"
cat > "$WORKDIR3/bin/sudo" <<'STUB'
#!/usr/bin/env bash
echo "sudo $*" >> "$STUB_LOG"
exit 0
STUB
chmod +x "$WORKDIR3/bin/sudo"
export PATH="$WORKDIR3/bin:$PATH"

cd "$ROOT"
output=$(bash uninstall.sh --yes --aphotic-toml "$WORKDIR3/aphotic.toml" < /dev/null 2>&1)

grep -q -- "sudo rm -rf $GREETER_PROBE_DIR/xdg/quickshell/aphotic-greeter" "$STUB_LOG" \
  || fail "--yes did not remove the greeter scaffold, got: $(cat "$STUB_LOG")"
grep -q -- "Removed the Aphotic greeter." <<< "$output" \
  || fail "expected the greeter removal to be reported, got: $output"
grep -q 'sudo rm -rf /etc/' <<< "$(cat "$STUB_LOG")" \
  && fail "removal must target the probed tree, never the real /etc: $(cat "$STUB_LOG")"

echo "PASS: --yes removes the greeter scaffold, and only the one under test"

# greetd active: the guard is a refusal, not a prompt, so --yes must not
# reach the removal. It is the one thing in this script that must survive an
# unattended run.
#
# pacman is stubbed to report sddm absent. With greetd enabled and sddm gone
# the script cannot swap the display manager back, so the guard holds. Without
# the stub this depends on whether sddm happens to be installed here, and the
# stubbed sudo would report a successful swap regardless.
cat > "$WORKDIR3/bin/pacman" <<'STUB'
#!/usr/bin/env bash
echo "pacman $*" >> "$STUB_LOG"
exit 1
STUB
chmod +x "$WORKDIR3/bin/pacman"
cat > "$WORKDIR3/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB_LOG"
# greetd is enabled and active.
case "$*" in
  *is-enabled*|*is-active*) exit 0 ;;
esac
exit 0
STUB
chmod +x "$WORKDIR3/bin/systemctl"
: > "$STUB_LOG"
mkdir -p "$HOME/.config/waybar"
echo "current" > "$HOME/.config/waybar/config.jsonc"

cd "$ROOT"
output=$(bash uninstall.sh --yes --aphotic-toml "$WORKDIR3/aphotic.toml" < /dev/null 2>&1)

grep -q 'sudo rm -rf' "$STUB_LOG" \
  && fail "--yes removed the scaffold while greetd was the active display manager: $(cat "$STUB_LOG")"
grep -q -- 'not touching the greeter scaffold' <<< "$output" \
  || fail "expected the greetd refusal to be reported, got: $output"

echo "PASS: --yes does not override the greetd guard"
