#!/bin/bash
# install.sh
#
# Orchestrator only: parse flags, source the lib/install/*.sh stage
# modules, and call them in order. Every stage's actual body lives in
# lib/install/ -- see that directory for detection, prompts, package
# install, NVIDIA, config deploy, shell activation, wallpapers, and the
# Hyprland launch offer.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/lib/install/ui.sh"
source "$ROOT_DIR/lib/install/python.sh"
source "$ROOT_DIR/lib/install/aur.sh"
source "$ROOT_DIR/lib/install/multilib.sh"
source "$ROOT_DIR/lib/install/backup.sh"
source "$ROOT_DIR/lib/install/wizard.sh"
source "$ROOT_DIR/lib/install/blackarch.sh"
source "$ROOT_DIR/lib/install/exploit_disclaimer.sh"
source "$ROOT_DIR/lib/install/claude_hooks.sh"
source "$ROOT_DIR/lib/install/assistant.sh"
source "$ROOT_DIR/lib/install/nvidia.sh"
source "$ROOT_DIR/lib/install/packages.sh"
source "$ROOT_DIR/lib/install/detect.sh"
source "$ROOT_DIR/lib/install/system_prep.sh"
source "$ROOT_DIR/lib/install/config_deploy.sh"
source "$ROOT_DIR/lib/install/shell_activation.sh"
source "$ROOT_DIR/lib/install/wallpapers.sh"
source "$ROOT_DIR/lib/install/hyprland_launch.sh"
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
CONFIG_ONLY=0
LAYERS_KNOWN=0
NO_BACKUP=0
KEEP_BACKUPS=5
PROFILE=""
LAYERS=""
THEME=""
ASSISTANT=""
ACCEPT_EXPLOIT_DISCLAIMER=0
NVIDIA_DRIVER_ACTION=""
OPT_IN=0

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
                                ("exploit" is a convenience bundle of
                                exploit-recon+web+network; exploit-passwords/
                                -reversing/-forensics/-reporting/-wordlists
                                are separate opt-ins -- see
                                docs/exploit-layer.md). Any exploit-* layer
                                enables the BlackArch repo unless its own
                                sublayer doesn't need it (e.g. -reporting,
                                -wordlists).
  --opt-in                      Interactive layer picker (preset or
                                cherry-pick prompts). Without this flag (and
                                without --profile/--with), a fresh install
                                defaults to the daily-driver setup -- full
                                profile, no optional layers -- with zero
                                prompts. Layers can always be added later by
                                re-running install.sh --with <layers>.
  --accept-exploit-disclaimer   Required alongside --with when it includes
                                any exploit-* layer AND stdin isn't a TTY
                                (scripted/CI installs) -- confirms you've
                                read and agree to the authorized-use
                                disclaimer that would otherwise be shown
                                interactively.
  --theme <name>                Theme preset name
  --with-assistant               Install the Aphotic Assistant (local chatbot,
                                needs an NVIDIA GPU; implies the ai layer)
  --no-assistant                 Skip the Aphotic Assistant, don't ask
  --nvidia-driver <keep|reinstall>
                                Only relevant if an NVIDIA driver is already
                                installed: 'keep' leaves it alone (don't
                                install nvidia-open-dkms on top of it),
                                'reinstall' uninstalls whatever's there first
                                and installs Aphotic's recommended
                                nvidia-open-dkms. Interactive installs are
                                asked; non-interactive ones (no TTY) without
                                this flag default to 'keep' -- never touches
                                a working driver without being told to.
  --config-only                 Config sync only: back up, copy Configs/ over
                                ~/.config/, restart the shell. No package
                                installs, no system prep, no wizard, and
                                aphotic.toml is left exactly as it is. This
                                is the "I just want the latest Quickshell/
                                Hyprland config" path after a git pull.
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
    --opt-in) OPT_IN=1; shift ;;
    --theme) [[ -n "${2:-}" ]] || { echo -e "$CER - Missing value for $1"; exit 1; }; THEME="$2"; shift 2 ;;
    --with-assistant) ASSISTANT="true"; shift ;;
    --no-assistant) ASSISTANT="false"; shift ;;
    --accept-exploit-disclaimer) ACCEPT_EXPLOIT_DISCLAIMER=1; shift ;;
    --nvidia-driver) [[ -n "${2:-}" ]] || { echo -e "$CER - Missing value for $1 (keep|reinstall)"; exit 1; }; NVIDIA_DRIVER_ACTION="$2"; shift 2 ;;
    --config-only) CONFIG_ONLY=1; shift ;;
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

main() {
  clear
  print_banner

  print_stage 1 "Preflight"
  echo -e "$CNT - You are about to execute a script that would attempt to setup Hyprland."
  detect_environment

  if [[ "$CONFIG_ONLY" == "1" ]]; then
    load_saved_config
    LAYERS=$(expand_layer_bundles "$LAYERS")
    echo -e "$CNT - Config-sync mode: reusing saved config (profile=${PROFILE:-unset}, layers=${LAYERS:-none}). No packages will be installed."
    config_sync
    exit 0
  fi

  print_stage 2 "Configuration"

  # Raw (unexpanded) previous layers, straight from detect.sh's pass over
  # aphotic.toml -- exploit_disclaimer_gate does its own bundle expansion
  # on both sides of the diff.
  PREV_LAYERS="$DETECTED_APHOTIC_LAYERS"

  resolve_config
  LAYERS=$(expand_layer_bundles "$LAYERS")

  exploit_disclaimer_gate "$PREV_LAYERS"

  BLACKARCH_CONSENT_GIVEN=0
  if [[ "$(any_layer_requires_blackarch "$LAYERS")" == "true" && "$DRY_RUN" != "1" ]]; then
    print_blackarch_warning
    if confirm "Continue enabling BlackArch for the exploit-* layers that need it?" n; then
      BLACKARCH_CONSENT_GIVEN=1
    else
      echo -e "$CWR - Skipping the BlackArch-backed exploit-* layers."
      LAYERS=$(strip_layers_matching "$LAYERS" _predicate_requires_blackarch)
    fi
  fi

  ISNVIDIA="$DETECTED_NVIDIA_PRESENT"
  resolve_assistant

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

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "$CNT - [dry-run] plan:"
    echo "  profile: $PROFILE"
    echo "  layers: $LAYERS"
    echo "  nvidia: $ISNVIDIA"
    echo "  assistant: $ASSISTANT"
    if [[ "$ASSISTANT" == "true" ]]; then
      local dry_model
      dry_model=$(resolve_assistant_model_via_llmfit || true)
      if [[ -n "$dry_model" ]]; then
        echo "  would pull model: $dry_model [llmfit recommendation]"
      else
        echo "  would pull model: $ASSISTANT_FALLBACK_MODEL [fallback -- llmfit not installed yet]"
      fi
    fi
    echo "  prep packages:"
    echo "$prep_pkgs" | sed 's/^/    - /'
    echo "  main packages:"
    echo "$main_pkgs" | sed 's/^/    - /'
    if [[ "$ISNVIDIA" == "true" ]]; then
      echo "  would install Nvidia driver: matching kernel headers + nvidia-open-dkms"
      echo "  would regenerate initramfs/UKI (mkinitcpio -P)"
    fi
    echo "  would install hyprland"
    if [[ "$(any_layer_requires_blackarch "$LAYERS")" == "true" ]]; then
      ensure_blackarch_repo
    fi
    if [[ "$(any_layer_requires_multilib "$LAYERS")" == "true" ]]; then
      ensure_multilib_repo
    fi
    exit 0
  fi

  echo -e "$CNT - This script will run some commands that require sudo. You will be prompted to enter your password."

  print_stage 3 "System prep"
  configure_wifi_powersave
  ensure_base_devel

  echo -e "$CNT - Resolving AUR helper..."
  AUR_HELPER=$(ensure_aur_helper)
  echo -e "$COK - Using AUR helper: $AUR_HELPER"

  if [[ "$(any_layer_requires_blackarch "$LAYERS")" == "true" ]]; then
    echo -e "$CNT - Enabling the BlackArch repo for the exploit-* layers that need it..."
    ensure_blackarch_repo || { echo -e "$CER - Failed to enable the BlackArch repo; BlackArch-backed exploit-* packages will fail to install. See docs/exploit-layer.md."; }
  fi

  if [[ "$(any_layer_requires_multilib "$LAYERS")" == "true" ]]; then
    echo -e "$CNT - Enabling the multilib repo for the gaming layer's lib32-* packages..."
    ensure_multilib_repo || { echo -e "$CER - Failed to enable the multilib repo; lib32-gamemode/lib32-mangohud will fail to resolve (an AUR helper may fuzzy-match them to broken AUR packages like lib32-gamemode-git instead)."; }
  fi

  print_stage 4 "Backup"
  if [[ "$NO_BACKUP" != "1" ]]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    echo -e "$CNT - Snapshotting existing configs..."
    # Derived from Configs/ itself (rather than a hardcoded dir list) so this
    # snapshot always covers everything deploy_user_configs's `cp -R
    # Configs/* ~/.config/` is about to overwrite, even as new Configs/
    # subdirs are added later.
    mapfile -t CONFIG_DIRS < <(find "$ROOT_DIR/Configs" -maxdepth 1 -mindepth 1 -not -name '.*' -exec basename {} \;)
    snapshot_config "$TIMESTAMP" "${CONFIG_DIRS[@]}"
    prune_backups "$KEEP_BACKUPS"
    echo -e "$COK - Backup saved under $(backup_root)/$TIMESTAMP"
  else
    echo -e "$CWR - Skipping backup (--no-backup)."
  fi

  print_stage 5 "Installing packages"
  install_package_list "$prep_pkgs"

  setup_nvidia
  # Nvidia support has been built into the mainline "hyprland" package for a
  # while now; the "hyprland-nvidia" AUR package that used to carry the
  # patches is gone, so both paths install the same package.
  install_software hyprland

  install_package_list "$main_pkgs"

  if [[ "$ASSISTANT" == "true" ]]; then
    setup_assistant || echo -e "$CWR - Aphotic Assistant setup did not finish; see $INSTLOG. The rest of the install continues."
  fi

  enable_core_services

  print_stage 6 "Deploying configs"
  CFG_COPIED=0
  if confirm "Would you like to copy config files?" n; then
    CFG_COPIED=1
    deploy_user_configs
    setup_login_manager_theme
    install_vscode_extensions
  fi

  print_stage 7 "Shell setup"
  activate_starship
  activate_zsh
  offer_extra_wallpapers

  write_aphotic_toml "$APHOTIC_TOML" "$PROFILE" "$LAYERS" "$THEME" "$ISNVIDIA" "$AUR_HELPER" "$(date -Iseconds)"

  echo -e "\n\e[1;32m── Install summary ──\e[0m"
  echo -e "  Profile:       $PROFILE"
  echo -e "  Layers:        ${LAYERS:-none}"
  echo -e "  Theme:         $THEME"
  echo -e "  AUR helper:    $AUR_HELPER"
  echo -e "  Nvidia:        $ISNVIDIA"
  echo -e "  Assistant:     $ASSISTANT"
  echo -e "  Configs copied: $([[ "$CFG_COPIED" == "1" ]] && echo yes || echo no)"
  echo -e "  Config saved:  $APHOTIC_TOML"
  if [[ ",$LAYERS," == *",exploit-"* ]]; then
    echo -e "  Exploit disclaimer: $([[ -f "$EXPLOIT_ACK_FILE" ]] && echo "acknowledged, see $EXPLOIT_ACK_FILE" || echo "not recorded")"
  fi
  echo -e "$COK - Install complete."

  "$HOME/.local/bin/aphotic" whatsnew &>> "$INSTLOG" || true

  if [[ "$ISNVIDIA" == "true" ]]; then
    echo -e "$CAT - Since we attempted to setup an Nvidia GPU the script will now end and you should reboot."
    exit 0
  fi

  offer_start_hyprland
}

trap 'exit_code=$?; notice_exploit_failure "$exit_code"; exit "$exit_code"' EXIT

main "$@"
