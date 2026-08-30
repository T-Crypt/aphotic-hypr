#!/usr/bin/env bash
set -euo pipefail

detect_aur_helper() {
  if command -v yay >/dev/null 2>&1; then
    echo "yay"
  elif command -v paru >/dev/null 2>&1; then
    echo "paru"
  else
    echo ""
  fi
}

# makepkg -si resolves build deps and installs the finished package through
# pacman. Both need populated pacman databases under /var/lib/pacman/sync/;
# on a fresh or torn-down system those are empty, and makepkg then fails with
# "database file for 'core'/'extra'/'multilib' does not exist". The sync must
# happen before any `makepkg -si` (and before `ensure_base_devel`, which
# shells out to pacman -S) or yay is cloned, built, then silently never lands
# on PATH. This is the one step that must have actually succeeded to return.
ensure_pacman_db() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[dry-run] would run sudo pacman -Sy to sync package databases"
    return 0
  fi
  echo "Syncing pacman databases (required before building/installing AUR packages)..." >&2
  sudo pacman -Sy --noconfirm || {
    echo "Failed to sync pacman databases. Installer cannot reliably build AUR packages until this works." >&2
    echo "Fix it manually: sudo pacman -Sy" >&2
    return 1
  }
}

install_yay() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[dry-run] would clone and build yay from AUR"
    return 0
  fi
  rm -rf /tmp/yay-bootstrap
  git clone https://aur.archlinux.org/yay.git /tmp/yay-bootstrap || {
    echo "Failed to clone yay from AUR" >&2
    exit 1
  }
  (cd /tmp/yay-bootstrap && makepkg -si --noconfirm)
  # makepkg -si can fail to actually land the binary (build error, sudo
  # prompt timeout, a conflicting local package) while still returning a
  # permissive zero here in some cases -- don't claim success until yay
  # is actually resolvable again. PATH may cache the old lookup, so
  # rehash before the check.
  hash -r 2>/dev/null || true
  if ! command -v yay >/dev/null 2>&1; then
    echo "yay was built from AUR but is still not on PATH (looked for 'yay')." >&2
    echo "Install it manually: sudo pacman -S --needed base-devel git && git clone https://aur.archlinux.org/yay.git /tmp/yay && cd /tmp/yay && makepkg -si" >&2
    return 1
  fi
}

ensure_aur_helper() {
  local helper
  helper=$(detect_aur_helper)
  if [[ -z "$helper" ]]; then
    echo "No AUR helper found (yay/paru). Installing yay..." >&2
    ensure_pacman_db || return 1
    install_yay || return 1
    # Re-detect rather than assume: if the install above failed, yay is
    # gone too and we must not hand back a name that won't resolve.
    helper=$(detect_aur_helper)
    if [[ -z "$helper" ]]; then
      echo "No AUR helper (yay/paru) is available on PATH after install." >&2
      return 1
    fi
  fi
  echo "$helper"
}
