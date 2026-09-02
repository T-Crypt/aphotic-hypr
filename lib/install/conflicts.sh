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

# Shown once, by whichever of the two entry points below gets there
# first: the guided flow asks up front (so nothing is uninstalled after
# the summary the user already accepted), a flag-driven install asks
# in the system-prep stage as it always has.
_announce_conflicting_packages() {
  local pkg
  echo -e "\n$CAT - These programs are already installed and do the same jobs as parts of Aphotic's desktop:"
  for pkg in "$@"; do
    echo -e "    - $pkg  ($(conflicting_package_role "$pkg"))"
  done
  echo -e "$CWR - Left in place they usually start themselves from your old setup's config, and you end up with two"
  echo -e "$CWR   bars, two app launchers, or duplicate notifications. That is the most common reason a finished"
  echo -e "$CWR   install looks broken (issue #41). Nothing else on this machine needs them."
  CONFLICTS_ANNOUNCED=1
}

# Guided-flow entry point: asks the question early and only records the
# answer in STRIP_CONFLICTS. The removal itself still happens in
# check_conflicting_packages below, during system prep, after the guided
# summary has been accepted -- so this never uninstalls anything at the
# point it is asked.
prompt_conflicting_packages() {
  local found=() pkg
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && found+=("$pkg")
  done < <(detect_conflicting_ui_packages)

  [[ ${#found[@]} -eq 0 ]] && return 0
  [[ -n "${STRIP_CONFLICTS:-}" ]] && return 0

  _announce_conflicting_packages "${found[@]}"
  if confirm "Uninstall them as part of this install?" y; then
    STRIP_CONFLICTS="1"
  else
    STRIP_CONFLICTS="0"
  fi
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

  [[ "${CONFLICTS_ANNOUNCED:-0}" == "1" ]] || _announce_conflicting_packages "${found[@]}"

  local action="${STRIP_CONFLICTS:-}"
  if [[ -z "$action" ]]; then
    if [[ -t 0 ]]; then
      if confirm "Uninstall them now?" y; then
        action="1"
      else
        action="0"
      fi
    else
      echo -e "$CWR - Non-interactive install with no --strip-conflicts/--keep-conflicts flag -- leaving them installed. Pass --strip-conflicts to remove them automatically instead."
      action="0"
    fi
  fi

  if [[ "$action" != "1" ]]; then
    echo -e "$CNT - Leaving ${found[*]} installed. If you do end up with duplicate bars, launchers or notifications, remove them later with: sudo pacman -Rns ${found[*]}"
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo -e "$CNT - [dry-run] would run: sudo pacman -Rns --noconfirm ${found[*]}"
    return 0
  fi

  echo -e "$CNT - Removing ${found[*]}..."
  sudo pacman -Rns --noconfirm "${found[@]}" &>> "$INSTLOG" || echo -e "$CWR - Failed to remove some of: ${found[*]} -- see $INSTLOG. Something else may depend on them; check with 'pacman -Qi <pkg>' before forcing it with pacman -Rdd."
}
