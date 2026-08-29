#!/usr/bin/env bash
set -euo pipefail

PACMAN_CONF="/etc/pacman.conf"

multilib_repo_present() {
  grep -q '^\[multilib\]' "$PACMAN_CONF" 2>/dev/null
}

# Uncomments the stock [multilib] block that ships commented-out in
# pacman.conf on a fresh Arch install; appends a fresh one if that block
# isn't there. Without this, lib32-* packages (lib32-gamemode,
# lib32-mangohud) aren't in any enabled repo, so an AUR helper "fuzzy
# matches" them to unrelated AUR packages like lib32-gamemode-git --
# which then fails on its own unresolvable lib32-* deps (e.g. lib32-dbus)
# since multilib is still disabled. Enabling multilib up front avoids
# that whole detour.
ensure_multilib_repo() {
  if multilib_repo_present; then
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[dry-run] would enable the multilib repo in $PACMAN_CONF"
    return 0
  fi

  if grep -q '^#\[multilib\]' "$PACMAN_CONF" 2>/dev/null; then
    sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' "$PACMAN_CONF"
  else
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a "$PACMAN_CONF" >/dev/null
  fi
  sudo pacman -Sy --noconfirm
}

layer_requires_multilib() {
  local name="$1"
  local toml="$ROOT_DIR/profiles/layers/$name.toml"
  [[ -f "$toml" ]] || { echo "false"; return 0; }
  "$PYTHON_BIN" -c '
import sys, tomllib
try:
    d = tomllib.load(open(sys.argv[1], "rb"))
    print("true" if d.get("layer", {}).get("requires_multilib", False) else "false")
except Exception:
    print("false")
' "$toml" 2>/dev/null || echo "false"
}

any_layer_requires_multilib() {
  local csv="$1" name
  IFS=',' read -ra names <<< "$csv"
  for name in "${names[@]}"; do
    [[ "$(layer_requires_multilib "$name")" == "true" ]] && { echo "true"; return 0; }
  done
  echo "false"
}
