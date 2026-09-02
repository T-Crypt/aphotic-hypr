#!/usr/bin/env bash
# lib/install/hyprland_launch.sh
set -euo pipefail

offer_start_hyprland() {
  echo -e "\n$CNT - Aphotic is installed. You can sign in to it from the graphical login screen,"
  echo -e "$CNT   either by starting that now or by rebooting -- both work the same."
  confirm "Start the login screen now?" n || return 0
  exec sudo systemctl start sddm &>> "$INSTLOG"
}
