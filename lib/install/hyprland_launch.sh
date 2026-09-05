#!/usr/bin/env bash
# lib/install/hyprland_launch.sh
set -euo pipefail

offer_start_hyprland() {
  # A graphical session already running (Omarchy's sddm autologin, or
  # install.sh run from a terminal inside an existing session) has no login
  # screen to offer -- the shell was already restarted into it above.
  if systemctl --user is-active --quiet graphical-session.target; then
    echo -e "\n$CNT - Aphotic is installed and already running in your current session."
    echo -e "$CNT   Log out and back in (or reboot) any time for a fully clean session."
    return 0
  fi

  echo -e "\n$CNT - Aphotic is installed. You can sign in to it from the graphical login screen,"
  echo -e "$CNT   either by starting that now or by rebooting -- both work the same."
  confirm "Start the login screen now?" n || return 0
  exec sudo systemctl start sddm &>> "$INSTLOG"
}
