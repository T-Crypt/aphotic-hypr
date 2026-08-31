#!/usr/bin/env bash
set -euo pipefail

# Packages a previous rice/WM setup commonly leaves behind that fight
# Aphotic's own Quickshell-based bar/launcher/notification center/
# wallpaper daemon for the same role. None of Aphotic's own profiles or
# layers (profiles/base/*.toml, profiles/layers/*.toml) ever install any
# of these, so anything on this list came from somewhere else -- a prior
# sway/i3/other-WM setup on the same machine, most commonly. Left in
# place, they autostart from whatever old config referenced them and end
# up fighting Aphotic's shell for the same role (a second, unstyled bar;
# a second app launcher; two daemons racing for the DBus notification
# name). Issue #41 was exactly this: a leftover waybar produced a raw,
# unstyled bar and made a working install look broken.
CONFLICTING_UI_PACKAGES=(
  waybar waybar-git
  polybar
  eww eww-git
  ags ags-hyprland-git
  rofi rofi-wayland rofi-lbonn-wayland-git
  wofi
  dunst mako swaync
  hyprpaper swaybg
  swayidle
)

conflicting_package_role() {
  case "$1" in
    waybar|waybar-git|polybar|eww|eww-git|ags|ags-hyprland-git)
      echo "status bar -- Aphotic's is Quickshell (aphotic-shell.service)" ;;
    rofi|rofi-wayland|rofi-lbonn-wayland-git|wofi)
      echo "app launcher -- Aphotic's is built into the shell (SUPER+space)" ;;
    dunst|mako|swaync)
      echo "notifications -- Aphotic's shell runs its own notification center" ;;
    hyprpaper|swaybg)
      echo "wallpaper daemon -- Aphotic uses awww-daemon" ;;
    swayidle)
      echo "idle handling -- Aphotic uses hypridle" ;;
    *)
      echo "a role Aphotic's shell already owns" ;;
  esac
}

detect_conflicting_ui_packages() {
  local installed pkg
  installed=$(pacman -Qq 2>/dev/null || true)
  for pkg in "${CONFLICTING_UI_PACKAGES[@]}"; do
    grep -qxF "$pkg" <<< "$installed" && echo "$pkg"
  done
  return 0
}

# Interactive by default (matches install_nvidia_driver's keep/reinstall
# gate): asks once, defaults to removing since that's what avoids issue
# #41's failure mode, but never removes anything without either an
# explicit y at the prompt or an explicit --strip-conflicts/
# --keep-conflicts flag. A non-interactive run with neither flag leaves
# packages alone rather than guessing -- same "never touch what's
# already there without being told to" rule as the Nvidia driver gate.
check_conflicting_packages() {
  local found=() pkg
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && found+=("$pkg")
  done < <(detect_conflicting_ui_packages)

  [[ ${#found[@]} -eq 0 ]] && return 0

  echo -e "$CAT - Found packages already installed that Aphotic's shell replaces:"
  for pkg in "${found[@]}"; do
    echo -e "    - $pkg  ($(conflicting_package_role "$pkg"))"
  done
  echo -e "$CWR - Left running, these commonly autostart from an old WM config and fight Aphotic's shell for the same role -- this is what issue #41 turned out to be."

  local action="${STRIP_CONFLICTS:-}"
  if [[ -z "$action" ]]; then
    if [[ -t 0 ]]; then
      read -rep $'[\e[1;33mACTION\e[0m] - Remove them now? (Y,n) ' STRIP_CHOICE
      [[ "$STRIP_CHOICE" == "n" || "$STRIP_CHOICE" == "N" ]] && action="0" || action="1"
    else
      echo -e "$CWR - Non-interactive install with no --strip-conflicts/--keep-conflicts flag -- leaving them installed. Pass --strip-conflicts to remove them automatically instead."
      action="0"
    fi
  fi

  if [[ "$action" != "1" ]]; then
    echo -e "$CNT - Leaving ${found[*]} installed. Remove by hand later if you hit duplicate bars/launchers/notifications: sudo pacman -Rns ${found[*]}"
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo -e "$CNT - [dry-run] would run: sudo pacman -Rns --noconfirm ${found[*]}"
    return 0
  fi

  echo -e "$CNT - Removing ${found[*]}..."
  sudo pacman -Rns --noconfirm "${found[@]}" &>> "$INSTLOG" || echo -e "$CWR - Failed to remove some of: ${found[*]} -- see $INSTLOG. Something else may depend on them; check with 'pacman -Qi <pkg>' before forcing it with pacman -Rdd."
}
