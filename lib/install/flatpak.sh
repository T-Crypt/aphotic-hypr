#!/usr/bin/env bash
# lib/install/flatpak.sh
#
# Optional applications installed through Flathub. Flatpak packages are never
# in the pacman data set that profiles describe (props/provided by Flathub,
# not Arch), so they live in an optional `[flatpak] apps = [...]` table of
# the base and layer TOMLs and in profiles/custom_flatpaks.lst. This module
# mirrors the data/optional/fatal distinction that lib/install/packages.sh
# applies to pacman packages: every Flatpak app is optional and a failure is
# reported and skipped, never fatal.
#
# Called after the main package list, since the `flatpak` binary itself ships
# in [packages] main and must be on PATH before anything here runs.
set -euo pipefail

FAILED_FLATPAK_APPS=()

_flatpak_installed() {
  flatpak info --system "$1" &>/dev/null
}

ensure_flathub() {
  if flatpak remotes --system 2>/dev/null | awk '{print $1}' | grep -qx -- flathub; then
    return 0
  fi
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo -e "$CNT - [dry-run] would add the Flathub remote"
    return 0
  fi
  echo -e "$CNT - Adding the Flathub remote..."
  if ! sudo flatpak remote-add --if-not-exists --system \
      flathub https://flathub.org/repo/flathub.flatpakrepo &>> "$INSTLOG"; then
    echo -e "$CWR - Could not add the Flathub remote; Flatpak installs will fail until it exists."
    return 1
  fi
  return 0
}

# install_flatpak_app <id>
install_flatpak_app() {
  local id="$1"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo -e "$CNT - [dry-run] would install Flatpak $id"
    return 0
  fi
  if ! command -v flatpak >/dev/null 2>&1; then
    FAILED_FLATPAK_APPS+=("$id")
    echo -e "$CER - flatpak is not installed, so $id was skipped."
    return 0
  fi
  if _flatpak_installed "$id"; then
    echo -e "$COK - Flatpak $id is already installed."
    return 0
  fi
  [[ -t 1 ]] || echo -en "$CNT - Now installing Flatpak $id "
  local rc=0 pid
  sudo flatpak install --system -y flathub "$id" &>> "$INSTLOG" &
  pid=$!
  show_progress "$pid" "installing $id"
  wait "$pid" 2>/dev/null || rc=$?
  if _flatpak_installed "$id"; then
    echo -e "$COK - Flatpak $id was installed."
    return 0
  fi
  if ((rc == 130 || rc == 143)); then
    echo -e "$CER - Interrupted while installing $id -- stopping here. Nothing further will be installed."
    exit "$rc"
  fi
  FAILED_FLATPAK_APPS+=("$id")
  echo -e "$CER - Flatpak $id failed to install."
  echo -e "$CWR   Skipped, the install continues. Output: $INSTLOG"
  return 0
}

install_flatpak_list() {
  local apps="$1" id
  [[ -n "$apps" ]] || return 0
  ensure_flathub || true
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    install_flatpak_app "$id"
  done <<< "$apps"
}

print_flatpak_plan() {
  local apps="$1" id
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    echo "    - $id (optional: a failure is reported, not fatal)"
  done <<< "$apps"
}

report_failed_flatpak_apps() {
  ((${#FAILED_FLATPAK_APPS[@]} > 0)) || return 0
  echo -e "\n\e[1;31m── ${#FAILED_FLATPAK_APPS[@]} Flatpak app(s) failed to install ──\e[0m"
  echo -e "  None are part of the shell itself. Install them later with: sudo flatpak install flathub <app-id>"
  for id in "${FAILED_FLATPAK_APPS[@]}"; do
    echo "    - $id"
  done
  echo -e "  Full output: $INSTLOG"
}
