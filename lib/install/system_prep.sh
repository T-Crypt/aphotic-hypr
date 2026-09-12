#!/usr/bin/env bash
# lib/install/system_prep.sh
set -euo pipefail

ensure_base_devel() {
  command -v fakeroot >/dev/null 2>&1 && return 0
  echo -e "$CNT - base-devel not found; installing it now (required to build AUR packages)."
  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "$CNT - [dry-run] would install base-devel"
    return 0
  fi
  sudo pacman -S --needed --noconfirm base-devel &>> "$INSTLOG" || { echo -e "$CER - Failed to install base-devel. Install it manually: sudo pacman -S base-devel"; exit 1; }
}

# bluetooth + sddm + removing desktop portals that conflict with the ones
# Aphotic's own package list pulls in -- always run once the main package
# list has installed, regardless of which layers were selected.
enable_core_services() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "$CNT - [dry-run] would enable bluetooth.service and sddm, and remove xdg-desktop-portal-gnome/-gtk"
    return 0
  fi
  echo -e "$CNT - Enabling bluetooth service..."
  sudo systemctl enable --now bluetooth.service &>> "$INSTLOG"
  echo -e "$CNT - Enabling display manager (sddm)..."
  sudo systemctl enable sddm &>> "$INSTLOG"
  # pacman, not "$AUR_HELPER": a removal never needs an AUR helper, and an
  # empty one (failed yay bootstrap) would just run as the empty command.
  # Only name portals that are actually installed -- pacman -R aborts the
  # whole transaction on the first "target not found", so passing both
  # unconditionally meant one absent portal left the other one installed.
  echo -e "$CNT - Removing conflicting desktop portals..."
  local portals=()
  local portal
  for portal in xdg-desktop-portal-gnome xdg-desktop-portal-gtk; do
    pacman -Qq "$portal" &>/dev/null && portals+=("$portal")
  done
  if ((${#portals[@]} > 0)); then
    sudo pacman -R --noconfirm "${portals[@]}" &>> "$INSTLOG" || true
  fi
}
