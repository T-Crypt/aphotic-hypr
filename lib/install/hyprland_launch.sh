#!/usr/bin/env bash
# lib/install/hyprland_launch.sh
set -euo pipefail

offer_start_hyprland() {
  confirm "Would you like to start Hyprland now?" n || return 0
  exec sudo systemctl start sddm &>> "$INSTLOG"
}
