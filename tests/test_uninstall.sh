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
echo "y" | bash uninstall.sh --aphotic-toml "$WORKDIR/aphotic.toml"

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
output=$(echo "y" | bash uninstall.sh --aphotic-toml "$WORKDIR2/aphotic.toml" 2>&1)
status=$?
set -e

[[ "$status" -ne 0 ]] || fail "expected non-zero exit when no backups found, got $status"
[[ "$output" != *"Uninstall complete."* ]] || fail "expected no 'Uninstall complete.' message, got: $output"

echo "PASS: uninstall fails loudly when no backups exist"
