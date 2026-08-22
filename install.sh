#!/bin/bash
# install.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/lib/install/python.sh"
source "$ROOT_DIR/lib/install/aur.sh"
source "$ROOT_DIR/lib/install/backup.sh"
source "$ROOT_DIR/lib/install/wizard.sh"
source "$ROOT_DIR/lib/install/blackarch.sh"
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
APHOTIC_TOML="$ROOT_DIR/aphotic.toml"

DRY_RUN=0
NO_BACKUP=0
KEEP_BACKUPS=5
PROFILE=""
LAYERS=""
THEME=""

TOTAL_STAGES=7
STAGE_COLORS=(35 36 33 34 32 36 35)

print_banner() {
  [[ -t 1 ]] || return 0
  echo -e "\e[1;35m"
  cat <<'EOF'
 ███╗   ██╗ ██████╗  ██████╗████████╗██╗███████╗
 ████╗  ██║██╔═══██╗██╔════╝╚══██╔══╝██║██╔════╝
 ██╔██╗ ██║██║   ██║██║        ██║   ██║███████╗
 ██║╚██╗██║██║   ██║██║        ██║   ██║╚════██║
 ██║ ╚████║╚██████╔╝╚██████╗   ██║   ██║███████║
 ╚═╝  ╚═══╝ ╚═════╝  ╚═════╝   ╚═╝   ╚═╝╚══════╝
        ██╗  ██╗██╗   ██╗██████╗ ██████╗
        ██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗
        ███████║ ╚████╔╝ ██████╔╝██████╔╝
        ██╔══██║  ╚██╔╝  ██╔══██╗██╔══██╗
        ██║  ██║   ██║   ██║  ██║██║  ██║
        ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝
EOF
  echo -e "\e[0m"
}

print_stage() {
  local num="$1" name="$2"
  local color="${STAGE_COLORS[$(((num - 1) % ${#STAGE_COLORS[@]}))]}"
  echo -e "\n\e[1;${color}m── [$num/$TOTAL_STAGES] $name ──\e[0m"
}

print_help() {
  cat <<'EOF'
Usage: ./install.sh [options]

  --profile <minimal|full>     Select base profile (skips wizard prompt)
  --with <layer,layer,...>     Comma-separated layers: gaming,dev,ai,exploit
                                (exploit enables the BlackArch repo -- see
                                docs/exploit-layer.md)
  --theme <name>                Theme preset name
  --dry-run                     Print planned actions, change nothing
  --no-backup                   Skip backing up existing configs
  --keep-backups <N>             Backups to retain (default: 5)
  -h, --help                     Show this help
  -v, --version                  Print the installed Aphotic version
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) [[ -n "${2:-}" ]] || { echo -e "$CER - Missing value for $1"; exit 1; }; PROFILE="$2"; shift 2 ;;
    --with) [[ -n "${2:-}" ]] || { echo -e "$CER - Missing value for $1"; exit 1; }; LAYERS="$2"; shift 2 ;;
    --theme) [[ -n "${2:-}" ]] || { echo -e "$CER - Missing value for $1"; exit 1; }; THEME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-backup) NO_BACKUP=1; shift ;;
    --keep-backups) [[ -n "${2:-}" ]] || { echo -e "$CER - Missing value for $1"; exit 1; }; KEEP_BACKUPS="$2"; shift 2 ;;
    -h|--help) print_help; exit 0 ;;
    -v|--version) cat "$ROOT_DIR/VERSION"; exit 0 ;;
    *) echo -e "$CER - Unknown option: $1"; print_help; exit 1 ;;
  esac
done

if ! [[ "$KEEP_BACKUPS" =~ ^[0-9]+$ ]]; then
  echo -e "$CER - --keep-backups requires a non-negative integer, got: $KEEP_BACKUPS"
  exit 1
fi

export DRY_RUN

if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
  echo -e "$CNT - Python not found; installing it now (required before package lists can be resolved)."
  if [[ "$DRY_RUN" != "1" ]]; then
    sudo pacman -S --needed --noconfirm python || { echo -e "$CER - Failed to install python. Install it manually: sudo pacman -S python"; exit 1; }
  fi
fi

PYTHON_BIN=$(resolve_python_bin) || { echo -e "$CER - Python is required but was not found. Install it first: sudo pacman -S python"; exit 1; }

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

detect_nvidia() {
  if lspci -k | grep -A 2 -E "(VGA|3D)" | grep -iq nvidia; then
    echo "true"
  else
    echo "false"
  fi
}

resolve_config() {
  if [[ -f "$APHOTIC_TOML" && -z "$PROFILE" && -z "$LAYERS" ]]; then
    local existing_profile existing_layers
    existing_profile=$("$PYTHON_BIN" -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["install"]["profile"])' "$APHOTIC_TOML")
    existing_layers=$("$PYTHON_BIN" -c 'import sys, tomllib; print(",".join(tomllib.load(open(sys.argv[1], "rb"))["install"]["layers"]))' "$APHOTIC_TOML")
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
}

main() {
  clear
  print_banner

  print_stage 1 "Preflight"
  echo -e "$CNT - You are about to execute a script that would attempt to setup Hyprland."

  echo -e "$CNT - Checking for Physical or VM..."
  ISVM=$(hostnamectl | grep Chassis || true)
  echo -e "Using $ISVM"
  if [[ "$ISVM" == *"vm"* ]]; then
    echo -e "$CWR - Please note that VMs are not fully supported and if you try to run this on a Virtual Machine there is a high chance this will fail."
  fi

  print_stage 2 "Configuration"
  resolve_config

  if [[ ",$LAYERS," == *",exploit,"* && "$DRY_RUN" != "1" ]]; then
    print_blackarch_warning
    read -rep $'[\e[1;33mACTION\e[0m] - Continue enabling the exploit layer / BlackArch repo? (y,N) ' EXPLOIT_OK
    if [[ "$EXPLOIT_OK" != "y" && "$EXPLOIT_OK" != "Y" ]]; then
      echo -e "$CWR - Skipping the exploit layer."
      LAYERS=$(echo ",$LAYERS," | sed 's/,exploit,/,/' | sed 's/^,//; s/,$//')
    fi
  fi

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
  main_pkgs=$("$PYTHON_BIN" "$ROOT_DIR/lib/toml/merge.py" --base "$ROOT_DIR/profiles/base/$PROFILE.toml" --layers "$layer_args" --custom-apps "$ROOT_DIR/profiles/custom_apps.lst" --field main) || { echo -e "$CER - Failed to resolve package list (check --profile/--with values)"; exit 1; }
  prep_pkgs=$("$PYTHON_BIN" "$ROOT_DIR/lib/toml/merge.py" --base "$ROOT_DIR/profiles/base/$PROFILE.toml" --layers "$layer_args" --field prep) || { echo -e "$CER - Failed to resolve package list (check --profile/--with values)"; exit 1; }

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
    if [[ ",$LAYERS," == *",exploit,"* ]]; then
      ensure_blackarch_repo
    fi
    exit 0
  fi

  echo -e "$CNT - This script will run some commands that require sudo. You will be prompted to enter your password."

  print_stage 3 "System prep"
  read -rep $'[\e[1;33mACTION\e[0m] - Would you like to disable WiFi powersave? (y,n) ' WIFI
  if [[ "$WIFI" == "Y" || "$WIFI" == "y" ]]; then
    if systemctl list-unit-files NetworkManager.service &>/dev/null; then
      echo -e "$CNT - Disabling WiFi powersave..."
      LOC="/etc/NetworkManager/conf.d/wifi-powersave.conf"
      if ! sudo grep -qF "wifi.powersave = 2" "$LOC" 2>/dev/null; then
        echo -e "[connection]\nwifi.powersave = 2" | sudo tee -a "$LOC" &>> "$INSTLOG"
      fi
      sudo systemctl restart NetworkManager &>> "$INSTLOG"
    else
      echo -e "$CWR - NetworkManager isn't installed; skipping WiFi powersave config."
    fi
  fi

  if ! command -v fakeroot >/dev/null 2>&1; then
    echo -e "$CNT - base-devel not found; installing it now (required to build AUR packages)."
    sudo pacman -S --needed --noconfirm base-devel &>> "$INSTLOG" || { echo -e "$CER - Failed to install base-devel. Install it manually: sudo pacman -S base-devel"; exit 1; }
  fi

  echo -e "$CNT - Resolving AUR helper..."
  AUR_HELPER=$(ensure_aur_helper)
  echo -e "$COK - Using AUR helper: $AUR_HELPER"

  if [[ ",$LAYERS," == *",exploit,"* ]]; then
    echo -e "$CNT - Enabling the BlackArch repo for the exploit layer..."
    ensure_blackarch_repo || { echo -e "$CER - Failed to enable the BlackArch repo; exploit-layer packages will fail to install. See docs/exploit-layer.md."; }
  fi

  print_stage 4 "Backup"
  if [[ "$NO_BACKUP" != "1" ]]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    echo -e "$CNT - Snapshotting existing configs..."
    # Derived from Configs/ itself (rather than a hardcoded dir list) so this
    # snapshot always covers everything stage 6's `cp -R Configs/* ~/.config/`
    # is about to overwrite, even as new Configs/ subdirs are added later.
    mapfile -t CONFIG_DIRS < <(find "$ROOT_DIR/Configs" -maxdepth 1 -mindepth 1 -not -name '.*' -exec basename {} \;)
    snapshot_config "$TIMESTAMP" "${CONFIG_DIRS[@]}"
    prune_backups "$KEEP_BACKUPS"
    echo -e "$COK - Backup saved under $(backup_root)/$TIMESTAMP"
  else
    echo -e "$CWR - Skipping backup (--no-backup)."
  fi

  print_stage 5 "Installing packages"
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && install_software "$pkg"
  done <<< "$prep_pkgs"

  if [[ "$ISNVIDIA" == "true" ]]; then
    echo -e "$CNT - Configuring Nvidia modules..."
    sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img
    if ! sudo grep -qF "options nvidia-drm modeset=1" /etc/modprobe.d/nvidia.conf 2>/dev/null; then
      echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf &>> "$INSTLOG"
    fi

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

  echo -e "$CNT - Enabling bluetooth service..."
  sudo systemctl enable --now bluetooth.service &>> "$INSTLOG"
  echo -e "$CNT - Enabling display manager (sddm)..."
  sudo systemctl enable sddm &>> "$INSTLOG"
  echo -e "$CNT - Removing conflicting desktop portals..."
  "$AUR_HELPER" -R --noconfirm xdg-desktop-portal-gnome xdg-desktop-portal-gtk &>> "$INSTLOG" || true

  print_stage 6 "Deploying configs"
  read -rep $'[\e[1;33mACTION\e[0m] - Would you like to copy config files? (y,n) ' CFG
  CFG_COPIED=0
  if [[ "$CFG" == "Y" || "$CFG" == "y" ]]; then
    CFG_COPIED=1
    echo -e "$CNT - Copying config files..."
    CUSTOM_LUA="$HOME/.config/hypr/custom.lua"
    CUSTOM_LUA_BACKUP=""
    if [[ -f "$CUSTOM_LUA" ]]; then
      CUSTOM_LUA_BACKUP=$(mktemp)
      cp "$CUSTOM_LUA" "$CUSTOM_LUA_BACKUP"
    fi

    cp -R "$ROOT_DIR/Configs/"* "$HOME/.config/"
    chmod +x "$HOME/.config/hypr/scripts/"*

    if [[ -n "$CUSTOM_LUA_BACKUP" ]]; then
      cp "$CUSTOM_LUA_BACKUP" "$CUSTOM_LUA"
      rm -f "$CUSTOM_LUA_BACKUP"
      echo -e "$CNT - Preserved your existing hypr/custom.lua"
    fi

    mkdir -p "$HOME/.local/bin"
    ln -sf "$ROOT_DIR/Configs/.local/bin/aphotic" "$HOME/.local/bin/aphotic"

    echo -e "$CNT - Enabling the Aphotic shell restart-supervision unit..."
    mkdir -p "$HOME/.config/systemd/user"
    systemctl --user daemon-reload &>> "$INSTLOG"
    systemctl --user enable aphotic-shell.service &>> "$INSTLOG" || echo -e "$CWR - Could not enable aphotic-shell.service; the shell will still start via Hyprland's exec-once but won't auto-restart on crash."

    # Make sure `aphotic` (and anything else under ~/.local/bin) resolves on
    # PATH without relying on the optional zsh-activation step below, since
    # bash users need this too and Configs/.zshrc only lands on disk if they
    # opt in.
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
      [[ "$rc" == "$HOME/.zshrc" && ! -f "$rc" ]] && continue
      touch "$rc"
      if ! grep -qF '.local/bin' "$rc"; then
        printf '\n# Added by aphotic install.sh so ~/.local/bin (aphotic CLI) is on PATH\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
      fi
    done

    KVARCDARK_SVG="/usr/share/Kvantum/KvArcDark/KvArcDark.svg"
    mkdir -p "$HOME/.config/Kvantum/Aphotic"
    if [[ -f "$KVARCDARK_SVG" ]]; then
      cp "$KVARCDARK_SVG" "$HOME/.config/Kvantum/Aphotic/Aphotic.svg"
    else
      echo -e "$CWR - KvArcDark theme assets not found at $KVARCDARK_SVG (should ship with the kvantum package); Kvantum will fall back to its default style."
    fi

    if [[ "$ISNVIDIA" == "true" ]]; then
      echo -e '\nrequire("nvidia")' >> "$HOME/.config/hypr/hyprland.lua"
    fi

    echo -e "$CNT - Setting up the login screen..."
    sudo tar -xf "$ROOT_DIR/src/sugar-candy.tar.gz" -C /usr/share/sddm/themes/
    sudo chown -R "$USER:$USER" /usr/share/sddm/themes/sugar-candy
    sudo mkdir -p /etc/sddm.conf.d
    if ! sudo grep -qF "Current=sugar-candy" /etc/sddm.conf.d/10-theme.conf 2>/dev/null; then
      echo -e "[Theme]\nCurrent=sugar-candy" | sudo tee -a /etc/sddm.conf.d/10-theme.conf &>> "$INSTLOG"
    fi
    WLDIR=/usr/share/wayland-sessions
    [[ -d "$WLDIR" ]] || sudo mkdir -p "$WLDIR"
    sudo cp "$ROOT_DIR/src/hyprland.desktop" /usr/share/wayland-sessions/

    echo -e "$CNT - Adding VScode Extensions..."
    mkdir -p "$HOME/.vscode"
    tar -xf "$ROOT_DIR/src/extensions.tar.gz" -C "$HOME/.vscode/"
  fi

  print_stage 7 "Shell setup"
  read -rep $'[\e[1;33mACTION\e[0m] - Would you like to activate the starship shell? (y,n) ' STAR
  if [[ "$STAR" == "Y" || "$STAR" == "y" ]]; then
    echo -e "$CNT - Activating starship..."
    if ! grep -qF 'starship init bash' "$HOME/.bashrc" 2>/dev/null; then
      echo -e '\neval "$(starship init bash)"' >> "$HOME/.bashrc"
    fi
    cp "$ROOT_DIR/src/starship.toml" "$HOME/.config/"
  fi

  read -rep $'[\e[1;33mACTION\e[0m] - Would you like to activate zsh shell? (y,n) ' ZSH
  if [[ "$ZSH" == "Y" || "$ZSH" == "y" ]]; then
    echo -e "$CNT - Activating zsh..."
    cp "$ROOT_DIR/Configs/.p10k.zsh" "$HOME"
    cp "$ROOT_DIR/Configs/.zshrc" "$HOME"
    chsh -s "$(which zsh)"
  fi

  write_aphotic_toml "$APHOTIC_TOML" "$PROFILE" "$LAYERS" "$THEME" "$ISNVIDIA" "$AUR_HELPER" "$(date -Iseconds)"

  echo -e "\n\e[1;32m── Install summary ──\e[0m"
  echo -e "  Profile:       $PROFILE"
  echo -e "  Layers:        ${LAYERS:-none}"
  echo -e "  Theme:         $THEME"
  echo -e "  AUR helper:    $AUR_HELPER"
  echo -e "  Nvidia:        $ISNVIDIA"
  echo -e "  Configs copied: $([[ "$CFG_COPIED" == "1" ]] && echo yes || echo no)"
  echo -e "  Config saved:  $APHOTIC_TOML"
  echo -e "$COK - Install complete."

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
