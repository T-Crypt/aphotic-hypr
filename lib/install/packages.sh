#!/usr/bin/env bash
# lib/install/packages.sh
set -euo pipefail

show_progress() {
  local pid="$1"
  if [[ -t 1 ]]; then
    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while ps | grep "$pid" &> /dev/null; do
      printf "\r\e[K%s" "${frames:i++%${#frames}:1}"
      sleep 0.1
    done
    printf "\r\e[K"
  else
    echo -n "working..."
    while ps | grep "$pid" &> /dev/null; do
      sleep 2
    done
    echo ""
  fi
}

install_software() {
  if "$AUR_HELPER" -Q "$1" &>> /dev/null ; then
    echo -e "$COK - $1 is already installed."
    return 0
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "$CNT - [dry-run] would install $1"
    return 0
  fi
  echo -en "$CNT - Now installing $1 "
  "$AUR_HELPER" -S --noconfirm "$1" &>> "$INSTLOG" &
  show_progress $!
  if "$AUR_HELPER" -Q "$1" &>> /dev/null ; then
    echo -e "\e[1A\e[K$COK - $1 was installed."
  else
    echo -e "\e[1A\e[K$CER - $1 install had failed, please check the install.log"
    exit 1
  fi
}

# Installs each newline-separated package name in $1, skipping blank lines.
install_package_list() {
  local pkgs="$1"
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && install_software "$pkg"
  done <<< "$pkgs"
}
