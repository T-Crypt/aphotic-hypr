#!/usr/bin/env bash
# lib/install/display_manager.sh
# Makes the Aphotic greeter (greetd) the login screen. sddm stays installed
# as the way back: `aphotic displaymanager switch sddm --confirm-tested`.

APHOTIC_GREETD_CONFIG="${APHOTIC_GREETD_CONFIG:-/etc/greetd/config.toml}"
APHOTIC_GREETD_BACKUP="${APHOTIC_GREETD_BACKUP:-/etc/greetd/config.toml.aphotic-backup}"
APHOTIC_GREETER_QML="${APHOTIC_GREETER_QML:-/etc/xdg/quickshell/aphotic-greeter/shell.qml}"
APHOTIC_GREETER_HYPR_CONF="${APHOTIC_GREETER_HYPR_CONF:-/etc/greetd/aphotic/hyprland-greeter.lua}"
APHOTIC_DM_CHOICE_FILE="${APHOTIC_DM_CHOICE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/aphotic/displaymanager}"

# Prints why the switch must not happen and returns 0, or returns 1 when it
# is safe. Omarchy keeps its own sddm autologin, and a user who switched
# back to sddm stays there through every later update.
greetd_switch_blocker() {
  if [[ "${APHOTIC_CONTAINER:-0}" == "1" ]]; then echo "container"; return 0; fi
  if [[ "${KEEP_SDDM:-0}" == "1" ]]; then echo "--keep-sddm"; return 0; fi
  if [[ "${DETECTED_OMARCHY:-0}" == "1" ]]; then echo "Omarchy keeps its own login"; return 0; fi
  if [[ "$(cat "$APHOTIC_DM_CHOICE_FILE" 2>/dev/null)" == "sddm" ]]; then echo "you chose sddm"; return 0; fi
  if ! command -v greetd &>/dev/null; then echo "greetd is not installed; run ./install.sh to add it"; return 0; fi
  if ! command -v start-hyprland &>/dev/null; then echo "start-hyprland is missing; update Hyprland to 0.56 or newer"; return 0; fi
  if ! command -v qs &>/dev/null; then echo "quickshell is not installed"; return 0; fi
  if [[ ! -f "$APHOTIC_GREETER_QML" || ! -f "$APHOTIC_GREETER_HYPR_CONF" ]]; then echo "the greeter files did not deploy"; return 0; fi
  return 1
}

activate_greetd() {
  local reason
  if reason="$(greetd_switch_blocker)"; then
    echo -e "$CNT - Login screen: keeping the current one ($reason)."
    return 0
  fi
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo -e "$CNT - [dry-run] would make the Aphotic greeter (greetd) the login screen; sddm stays installed"
    return 0
  fi

  if [[ -f "$APHOTIC_GREETD_CONFIG" && ! -f "$APHOTIC_GREETD_BACKUP" ]]; then
    sudo cp "$APHOTIC_GREETD_CONFIG" "$APHOTIC_GREETD_BACKUP"
  fi
  # Rewritten on every run, so an install switched on an older release
  # moves to the current compositor config.
  sudo cp "$ROOT_DIR/Configs/greetd/config.toml" "$APHOTIC_GREETD_CONFIG"

  if systemctl is-enabled greetd.service &>/dev/null; then
    echo -e "$COK - Login screen: the Aphotic greeter (config refreshed)."
    return 0
  fi
  sudo systemctl disable sddm.service &>> "$INSTLOG" || true
  if ! sudo systemctl enable greetd.service &>> "$INSTLOG"; then
    echo -e "$CWR - Could not enable greetd; putting sddm back."
    sudo systemctl enable sddm.service &>> "$INSTLOG" || true
    return 1
  fi
  echo -e "$COK - Login screen: the Aphotic greeter, from your next boot."
  echo -e "$CNT   To go back to sddm: aphotic displaymanager switch sddm --confirm-tested"
}

# Deploys the greeter and switches to it. Skipped where greetd is absent,
# which leaves the login screen exactly as it was.
install_greeter() {
  [[ "${APHOTIC_CONTAINER:-0}" == "1" || "${GREETD_PREVIEW:-1}" != "1" ]] && return 0
  command -v greetd &>/dev/null || return 0
  if ! can_sudo; then
    echo -e "$CWR - The login screen needs sudo; run 'aphotic sync' from a terminal to update it."
    return 0
  fi
  if setup_greetd_greeter; then
    activate_greetd || true
  else
    echo -e "$CWR - The greeter did not deploy; see $INSTLOG. Your login screen is unchanged."
  fi
}

# sudo from `aphotic update` may have no terminal to ask for a password on.
can_sudo() {
  sudo -n true &>/dev/null || [[ -t 0 ]]
}
