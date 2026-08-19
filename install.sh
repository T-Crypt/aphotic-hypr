#!/bin/bash
# install.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/lib/install/python.sh"
source "$ROOT_DIR/lib/install/aur.sh"
source "$ROOT_DIR/lib/install/backup.sh"
source "$ROOT_DIR/lib/install/wizard.sh"
# sourced libs each set -euo pipefail, which otherwise leaks into this
# script's shell options since `set` is not scoped to the sourced file
set +euo pipefail

CNT="[\e[1;36mNOTE\e[0m]"
COK="[\e[1;32mOK\e[0m]"
CER="[\e[1;31mERROR\e[0m]"
CWR="[\e[1;35mWARNING\e[0m]"
CAT="[\e[1;37mATTENTION\e[0m]"
CAC="[\e[1;33mACTION\e[0m]"
INSTLOG="install.log"
NOCTIS_TOML="$ROOT_DIR/noctis.toml"

DRY_RUN=0
NO_BACKUP=0
KEEP_BACKUPS=5
PROFILE=""
LAYERS=""
THEME=""
BAR_POSITION=""

print_help() {
  cat <<'EOF'
Usage: ./install.sh [options]

  --profile <minimal|full>     Select base profile (skips wizard prompt)
  --with <layer,layer,...>     Comma-separated layers: gaming,dev,ai
  --theme <name>                Theme preset name
  --bar-position <top|left>     Initial waybar position
  --dry-run                     Print planned actions, change nothing
  --no-backup                   Skip backing up existing configs
  --keep-backups <N>             Backups to retain (default: 5)
  -h, --help                     Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --with) LAYERS="$2"; shift 2 ;;
    --theme) THEME="$2"; shift 2 ;;
    --bar-position) BAR_POSITION="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-backup) NO_BACKUP=1; shift ;;
    --keep-backups) KEEP_BACKUPS="$2"; shift 2 ;;
    -h|--help) print_help; exit 0 ;;
    *) echo -e "$CER - Unknown option: $1"; print_help; exit 1 ;;
  esac
done
export DRY_RUN
PYTHON_BIN=$(resolve_python_bin)

show_progress() {
  while ps | grep "$1" &> /dev/null; do
    echo -n "."
    sleep 2
  done
  echo -en "Done!\n"
  sleep 2
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
  echo -en "$CNT - Now installing $1 ."
  "$AUR_HELPER" -S --noconfirm "$1" &>> "$INSTLOG" &
  show_progress $!
  if "$AUR_HELPER" -Q "$1" &>> /dev/null ; then
    echo -e "\e[1A\e[K$COK - $1 was installed."
  else
    echo -e "\e[1A\e[K$CER - $1 install had failed, please check the install.log"
    exit 1
  fi
}

detect_nvidia() {
  if lspci -k | grep -A 2 -E "(VGA|3D)" | grep -iq nvidia; then
    echo "true"
  else
    echo "false"
  fi
}

resolve_config() {
  if [[ -f "$NOCTIS_TOML" && -z "$PROFILE" && -z "$LAYERS" ]]; then
    local existing_profile existing_layers
    existing_profile=$("$PYTHON_BIN" -c "import tomllib; print(tomllib.load(open('$NOCTIS_TOML','rb'))['install']['profile'])")
    existing_layers=$("$PYTHON_BIN" -c "import tomllib; print(','.join(tomllib.load(open('$NOCTIS_TOML','rb'))['install']['layers']))")
    echo -e "$CNT - Existing config found (profile=$existing_profile, layers=$existing_layers)."
    read -rep $'[\e[1;33mACTION\e[0m] - Reinstall same config? (Y,n) ' REUSE
    if [[ "$REUSE" != "n" && "$REUSE" != "N" ]]; then
      PROFILE="$existing_profile"
      LAYERS="$existing_layers"
    fi
  fi

  [[ -z "$PROFILE" ]] && PROFILE=$(prompt_profile)
  [[ -z "$LAYERS" ]] && LAYERS=$(prompt_layers)
  [[ -z "$THEME" ]] && THEME=$(prompt_theme)
  [[ -z "$BAR_POSITION" ]] && BAR_POSITION=$(prompt_bar_position)
}

main() {
  clear
  echo -e "$CNT - You are about to execute a script that would attempt to setup Hyprland."

  echo -e "$CNT - Checking for Physical or VM..."
  ISVM=$(hostnamectl | grep Chassis || true)
  echo -e "Using $ISVM"
  if [[ "$ISVM" == *"vm"* ]]; then
    echo -e "$CWR - Please note that VMs are not fully supported and if you try to run this on a Virtual Machine there is a high chance this will fail."
  fi

  resolve_config

  local layer_paths=()
  if [[ -n "$LAYERS" ]]; then
    IFS=',' read -ra layer_names <<< "$LAYERS"
    for name in "${layer_names[@]}"; do
      layer_paths+=("$ROOT_DIR/profiles/layers/$name.toml")
    done
  fi
  local layer_args=""
  if [[ ${#layer_paths[@]} -gt 0 ]]; then
    layer_args=$(IFS=,; echo "${layer_paths[*]}")
  fi

  local main_pkgs prep_pkgs
  main_pkgs=$("$PYTHON_BIN" "$ROOT_DIR/lib/toml/merge.py" --base "$ROOT_DIR/profiles/base/$PROFILE.toml" --layers "$layer_args" --custom-apps "$ROOT_DIR/profiles/custom_apps.lst" --field main)
  prep_pkgs=$("$PYTHON_BIN" "$ROOT_DIR/lib/toml/merge.py" --base "$ROOT_DIR/profiles/base/$PROFILE.toml" --layers "$layer_args" --field prep)

  ISNVIDIA=$(detect_nvidia)

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "$CNT - [dry-run] plan:"
    echo "  profile: $PROFILE"
    echo "  layers: $LAYERS"
    echo "  nvidia: $ISNVIDIA"
    echo "  prep packages:"
    echo "$prep_pkgs" | sed 's/^/    - /'
    echo "  main packages:"
    echo "$main_pkgs" | sed 's/^/    - /'
    if [[ "$ISNVIDIA" == "true" ]]; then
      echo "  would install hyprland-nvidia"
    else
      echo "  would install hyprland"
    fi
    exit 0
  fi

  echo -e "$CNT - This script will run some commands that require sudo. You will be prompted to enter your password."

  read -rep $'[\e[1;33mACTION\e[0m] - Would you like to disable WiFi powersave? (y,n) ' WIFI
  if [[ "$WIFI" == "Y" || "$WIFI" == "y" ]]; then
    LOC="/etc/NetworkManager/conf.d/wifi-powersave.conf"
    echo -e "[connection]\nwifi.powersave = 2" | sudo tee -a "$LOC" &>> "$INSTLOG"
    sudo systemctl restart NetworkManager &>> "$INSTLOG"
  fi

  AUR_HELPER=$(ensure_aur_helper)

  if [[ "$NO_BACKUP" != "1" ]]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    snapshot_config "$TIMESTAMP" hypr waybar kitty mako
    prune_backups "$KEEP_BACKUPS"
  fi

  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && install_software "$pkg"
  done <<< "$prep_pkgs"

  if [[ "$ISNVIDIA" == "true" ]]; then
    sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img
    echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf &>> "$INSTLOG"

    if "$AUR_HELPER" -Q hyprland &>> /dev/null ; then
      "$AUR_HELPER" -R --noconfirm hyprland &>> "$INSTLOG"
    fi
    install_software hyprland-nvidia
  else
    install_software hyprland
  fi

  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && install_software "$pkg"
  done <<< "$main_pkgs"

  sudo systemctl enable --now bluetooth.service &>> "$INSTLOG"
  sudo systemctl enable sddm &>> "$INSTLOG"
  "$AUR_HELPER" -R --noconfirm xdg-desktop-portal-gnome xdg-desktop-portal-gtk &>> "$INSTLOG" || true

  read -rep $'[\e[1;33mACTION\e[0m] - Would you like to copy config files? (y,n) ' CFG
  if [[ "$CFG" == "Y" || "$CFG" == "y" ]]; then
    echo -e "$CNT - Copying config files..."
    cp -R "$ROOT_DIR/.configs/"* "$HOME/.config/"
    chmod +x "$HOME/.config/hypr/scripts/"*

    if [[ "$ISNVIDIA" == "true" ]]; then
      echo -e "\nsource = ~/.config/hypr/nvidia.conf" >> "$HOME/.config/hypr/hyprland.conf"
    fi

    echo -e "$CNT - Setting up the login screen."
    sudo tar -xf "$ROOT_DIR/src/sugar-candy.tar.gz" -C /usr/share/sddm/themes/
    sudo chown -R "$USER:$USER" /usr/share/sddm/themes/sugar-candy
    sudo mkdir -p /etc/sddm.conf.d
    echo -e "[Theme]\nCurrent=sugar-candy" | sudo tee -a /etc/sddm.conf.d/10-theme.conf &>> "$INSTLOG"
    WLDIR=/usr/share/wayland-sessions
    [[ -d "$WLDIR" ]] || sudo mkdir -p "$WLDIR"
    sudo cp "$ROOT_DIR/src/hyprland.desktop" /usr/share/wayland-sessions/

    echo -e "$CNT - Adding VScode Extensions"
    mkdir -p "$HOME/.vscode"
    tar -xf "$ROOT_DIR/src/extensions.tar.gz" -C "$HOME/.vscode/"

    echo -e "$CNT - Adding Fonts for Rofi"
    mkdir -p "$HOME/.local/share/fonts"
    cp "$ROOT_DIR/src/Icomoon-Feather.ttf" "$HOME/.local/share/fonts"
    fc-cache -fv
  fi

  read -rep $'[\e[1;33mACTION\e[0m] - Would you like to activate the starship shell? (y,n) ' STAR
  if [[ "$STAR" == "Y" || "$STAR" == "y" ]]; then
    echo -e '\neval "$(starship init bash)"' >> "$HOME/.bashrc"
    cp "$ROOT_DIR/src/starship.toml" "$HOME/.config/"
  fi

  read -rep $'[\e[1;33mACTION\e[0m] - Would you like to activate zsh shell? (y,n) ' ZSH
  if [[ "$ZSH" == "Y" || "$ZSH" == "y" ]]; then
    cp "$ROOT_DIR/.configs/.p10k.zsh" "$HOME"
    cp "$ROOT_DIR/.configs/.zshrc" "$HOME"
    chsh -s "$(which zsh)"
  fi

  write_noctis_toml "$NOCTIS_TOML" "$PROFILE" "$LAYERS" "$THEME" "$BAR_POSITION" "$ISNVIDIA" "$AUR_HELPER" "$(date -Iseconds)"
  echo -e "$COK - Install complete. Config written to noctis.toml."

  if [[ "$ISNVIDIA" == "true" ]]; then
    echo -e "$CAT - Since we attempted to setup an Nvidia GPU the script will now end and you should reboot."
    exit 0
  fi

  read -rep $'[\e[1;33mACTION\e[0m] - Would you like to start Hyprland now? (y,n) ' HYP
  if [[ "$HYP" == "Y" || "$HYP" == "y" ]]; then
    exec sudo systemctl start sddm &>> "$INSTLOG"
  fi
}

main "$@"
