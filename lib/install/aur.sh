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

install_yay() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[dry-run] would clone and build yay from AUR"
    return 0
  fi
  git clone https://aur.archlinux.org/yay.git /tmp/yay-bootstrap
  (cd /tmp/yay-bootstrap && makepkg -si --noconfirm)
}

ensure_aur_helper() {
  local helper
  helper=$(detect_aur_helper)
  if [[ -z "$helper" ]]; then
    echo "No AUR helper found (yay/paru). Installing yay..." >&2
    install_yay
    helper="yay"
  fi
  echo "$helper"
}
