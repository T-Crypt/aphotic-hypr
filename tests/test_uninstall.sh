#!/usr/bin/env bash
# tests/test_uninstall.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

export HOME="$WORKDIR/home"
export NOCTIS_BACKUP_ROOT="$WORKDIR/backups"
mkdir -p "$HOME/.config/waybar" "$NOCTIS_BACKUP_ROOT/20260101-000000/waybar"
echo "backed-up" > "$NOCTIS_BACKUP_ROOT/20260101-000000/waybar/config.jsonc"
echo "current" > "$HOME/.config/waybar/config.jsonc"

cat > "$WORKDIR/noctis.toml" <<'EOF'
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
echo "y" | bash uninstall.sh --noctis-toml "$WORKDIR/noctis.toml"

content=$(cat "$HOME/.config/waybar/config.jsonc")
[[ "$content" == "backed-up" ]] || fail "expected backup restored, got '$content'"

echo "PASS: uninstall restores latest backup"

# --- Test: no backups present -> uninstall must fail loudly, not report success ---
WORKDIR2=$(mktemp -d)
trap 'rm -rf "$WORKDIR" "$WORKDIR2"' EXIT

export HOME="$WORKDIR2/home"
export NOCTIS_BACKUP_ROOT="$WORKDIR2/backups"
mkdir -p "$HOME/.config"
# Intentionally do NOT create NOCTIS_BACKUP_ROOT — no backups exist at all.

cat > "$WORKDIR2/noctis.toml" <<'EOF'
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
output=$(echo "y" | bash uninstall.sh --noctis-toml "$WORKDIR2/noctis.toml" 2>&1)
status=$?
set -e

[[ "$status" -ne 0 ]] || fail "expected non-zero exit when no backups found, got $status"
[[ "$output" != *"Uninstall complete."* ]] || fail "expected no 'Uninstall complete.' message, got: $output"

echo "PASS: uninstall fails loudly when no backups exist"
