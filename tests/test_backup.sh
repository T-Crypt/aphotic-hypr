#!/usr/bin/env bash
# tests/test_backup.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/install/backup.sh"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

export HOME="$WORKDIR/home"
export APHOTIC_BACKUP_ROOT="$WORKDIR/backups"
mkdir -p "$HOME/.config/waybar"
echo "original" > "$HOME/.config/waybar/config.jsonc"

DRY_RUN=0 snapshot_config "20260101-000000" waybar
[[ -f "$APHOTIC_BACKUP_ROOT/20260101-000000/waybar/config.jsonc" ]] || fail "snapshot did not copy waybar config"

for ts in 20260102-000000 20260103-000000 20260104-000000 20260105-000000 20260106-000000; do
  mkdir -p "$APHOTIC_BACKUP_ROOT/$ts"
done

prune_backups 5
remaining=$(ls -1 "$APHOTIC_BACKUP_ROOT" | wc -l)
[[ "$remaining" -eq 5 ]] || fail "expected 5 backups after prune, got $remaining"
[[ ! -d "$APHOTIC_BACKUP_ROOT/20260101-000000" ]] || fail "oldest backup was not pruned"

echo "PASS: backup snapshot + prune"
