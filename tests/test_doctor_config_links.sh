#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
export HOME="$WORKDIR/home"
export APHOTIC_DOTS_DIR="$WORKDIR/dots"
mkdir -p "$HOME/.config/hypr" "$APHOTIC_DOTS_DIR/Configs/hypr" "$WORKDIR/worktree/Configs/hypr"
touch "$APHOTIC_DOTS_DIR/Configs/hypr/keybinds.lua" "$WORKDIR/worktree/Configs/hypr/theme.lua"

# shellcheck source=/dev/null
source "$ROOT/Configs/.local/lib/aphotic/commands/cmd_doctor.sh"

ln -s "$APHOTIC_DOTS_DIR/Configs/hypr/keybinds.lua" "$HOME/.config/hypr/keybinds.lua"
out="$(_aphotic_doctor_config_links)"
[[ "$out" == *"[ok]"* ]] || fail "links inside the checkout must pass, got: $out"

ln -s "$WORKDIR/gone/Configs/hypr/startup.lua" "$HOME/.config/hypr/startup.lua"
ln -s "$WORKDIR/worktree/Configs/hypr/theme.lua" "$HOME/.config/hypr/theme.lua"
out="$(_aphotic_doctor_config_links)"
[[ "$out" == *"[BROKEN]"*"startup.lua"* ]] || fail "a link into a deleted checkout must be BROKEN, got: $out"
[[ "$out" == *"theme.lua points outside"* ]] || fail "a link into another checkout must warn, got: $out"
[[ "$out" == *"aphotic sync"* ]] || fail "the fix must be named, got: $out"

echo "PASS: doctor config links"
