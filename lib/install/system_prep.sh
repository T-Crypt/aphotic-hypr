#!/usr/bin/env bash
# lib/install/system_prep.sh
set -euo pipefail

configure_wifi_powersave() {
  confirm "Would you like to disable WiFi powersave?" n || return 0

  if ! systemctl list-unit-files NetworkManager.service &>/dev/null; then
    echo -e "$CWR - NetworkManager isn't installed; skipping WiFi powersave config."
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "$CNT - [dry-run] would disable WiFi powersave via NetworkManager"
    return 0
  fi

  echo -e "$CNT - Disabling WiFi powersave..."
  local loc="/etc/NetworkManager/conf.d/wifi-powersave.conf"
  if ! sudo grep -qF "wifi.powersave = 2" "$loc" 2>/dev/null; then
    echo -e "[connection]\nwifi.powersave = 2" | sudo tee -a "$loc" &>> "$INSTLOG"
  fi
  sudo systemctl restart NetworkManager &>> "$INSTLOG"
}

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
  echo -e "$CNT - Removing conflicting desktop portals..."
  "$AUR_HELPER" -R --noconfirm xdg-desktop-portal-gnome xdg-desktop-portal-gtk &>> "$INSTLOG" || true
}
