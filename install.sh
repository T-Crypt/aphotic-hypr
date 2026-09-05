#!/bin/bash
# install.sh
#
# Orchestrator only: parse flags, source the lib/install/*.sh stage
# modules, and call them in order. Every stage's actual body lives in
# lib/install/ -- see that directory for detection, prompts, package
# install, NVIDIA, config deploy, shell activation, and the Hyprland
# launch offer.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/lib/install/ui.sh"
source "$ROOT_DIR/lib/install/python.sh"
source "$ROOT_DIR/lib/install/aur.sh"
source "$ROOT_DIR/lib/install/multilib.sh"
source "$ROOT_DIR/lib/install/backup.sh"
source "$ROOT_DIR/lib/install/wizard.sh"
source "$ROOT_DIR/lib/install/guided.sh"
source "$ROOT_DIR/lib/install/blackarch.sh"
source "$ROOT_DIR/lib/install/exploit_disclaimer.sh"
source "$ROOT_DIR/lib/install/conflicts.sh"
source "$ROOT_DIR/lib/install/assistant.sh"
source "$ROOT_DIR/lib/install/nvidia.sh"
source "$ROOT_DIR/lib/install/amd.sh"
source "$ROOT_DIR/lib/install/gpu_compute.sh"
source "$ROOT_DIR/lib/install/packages.sh"
source "$ROOT_DIR/lib/install/detect.sh"
source "$ROOT_DIR/lib/install/system_prep.sh"
source "$ROOT_DIR/lib/install/config_deploy.sh"
source "$ROOT_DIR/lib/install/shell_activation.sh"
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
GREETD_PREVIEW=0
ACCEPT_EXPLOIT_DISCLAIMER=0
NVIDIA_DRIVER_ACTION=""
OPT_IN=0
STRIP_CONFLICTS=""
COPY_CONFIGS=""
ACTIVATE_STARSHIP=""
ACTIVATE_ZSH=""

# The guided path (lib/install/guided.sh) is what a first-time user gets:
# it only engages for `./install.sh` with no options at all, on a real
# terminal. Any flag at all -- and any non-TTY stdin, i.e. CI or a piped
# install -- keeps the exact flag-driven/zero-prompt behavior it had
# before, which is what every scripted caller depends on.
GUIDED=0
FLAGS_SEEN=0

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

  Run with no options on a terminal for the guided setup: a few plain
  questions, then a summary to accept before anything is changed. Every
  option below opts out of that and takes the same flag-driven path as
  before (no options + no terminal, e.g. CI or a piped install, still
  installs the zero-prompt daily-driver default).

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
  --opt-in                      Just the interactive layer picker, without
                                the rest of the guided setup. Without any
                                flag and without a terminal, a fresh install
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
  --with-greetd-preview          Deploy the greetd/Quickshell greeter scaffold
                                (package, compositor config, greeter QML) as
                                an inert preview -- does NOT enable greetd or
                                touch sddm. Nothing about the active login
                                screen changes until you separately run
                                'aphotic displaymanager switch greetd' after
                                validating it (see that command's own
                                --confirm-tested gate).
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
  --strip-conflicts              Remove already-installed packages that
                                Aphotic's shell replaces (waybar, rofi/
                                wofi, dunst/mako/swaync, etc.) without
                                asking. Interactive installs are asked;
                                non-interactive ones default to leaving
                                them installed.
  --keep-conflicts                Leave those packages alone without
                                asking, even interactively.
  --dry-run                     Print planned actions, change nothing
  --no-backup                   Skip backing up existing configs
  --keep-backups <N>             Backups to retain (default: 5)
  -h, --help                     Show this help
  -v, --version                  Print the installed Aphotic version
EOF
}

while [[ $# -gt 0 ]]; do
  # -h/--help and -v/--version exit before this matters, so every flag that
  # reaches the parser body means "not a bare invocation" -- see GUIDED.
  case "$1" in
    -h|--help) print_help; exit 0 ;;
    -v|--version) cat "$ROOT_DIR/VERSION"; exit 0 ;;
  esac
  FLAGS_SEEN=1
  case "$1" in
    --profile) [[ -n "${2:-}" ]] || { echo -e "$CER - Missing value for $1"; exit 1; }; PROFILE="$2"; shift 2 ;;
    --with) [[ -n "${2:-}" ]] || { echo -e "$CER - Missing value for $1"; exit 1; }; LAYERS="$2"; shift 2 ;;
    --opt-in) OPT_IN=1; shift ;;
    --theme) [[ -n "${2:-}" ]] || { echo -e "$CER - Missing value for $1"; exit 1; }; THEME="$2"; shift 2 ;;
    --with-assistant) ASSISTANT="true"; shift ;;
    --no-assistant) ASSISTANT="false"; shift ;;
    --with-greetd-preview) GREETD_PREVIEW=1; shift ;;
    --accept-exploit-disclaimer) ACCEPT_EXPLOIT_DISCLAIMER=1; shift ;;
    --nvidia-driver) [[ -n "${2:-}" ]] || { echo -e "$CER - Missing value for $1 (keep|reinstall)"; exit 1; }; NVIDIA_DRIVER_ACTION="$2"; shift 2 ;;
    --config-only) CONFIG_ONLY=1; shift ;;
    --strip-conflicts) STRIP_CONFLICTS="1"; shift ;;
    --keep-conflicts) STRIP_CONFLICTS="0"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-backup) NO_BACKUP=1; shift ;;
    --keep-backups) [[ -n "${2:-}" ]] || { echo -e "$CER - Missing value for $1"; exit 1; }; KEEP_BACKUPS="$2"; shift 2 ;;
    *) echo -e "$CER - Unknown option: $1"; print_help; exit 1 ;;
  esac
done

if [[ "$FLAGS_SEEN" == "0" ]] && [[ -t 0 ]]; then
  GUIDED=1
fi

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

  # Aphotic depends on systemd directly, not just as whatever happens to
  # be PID 1 on Arch by default: SDDM, bluetooth.service, and the
  # aphotic-shell.service user unit that runs the actual Quickshell bar
  # (Configs/systemd/user/aphotic-shell.service) all assume it. A
  # non-systemd base (e.g. Artix/OpenRC or runit) would get through the
  # rest of this script and then have no working bar at all, with
  # nothing pointing back at why -- so this checks and fails fast
  # instead, for both a full install and --config-only (config-only
  # still restarts aphotic-shell.service via systemctl --user).
  if [[ ! -d /run/systemd/system ]]; then
    echo -e "$CER - systemd isn't running as PID 1 (no /run/systemd/system) -- Aphotic isn't supported on a non-systemd base. Nothing has been changed."
    exit 1
  fi

  if [[ "$GUIDED" == "1" ]]; then
    guided_intro
  else
    echo -e "$CNT - You are about to execute a script that would attempt to setup Hyprland."
  fi
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

  if [[ "$GUIDED" == "1" ]]; then
    guided_configure
  else
    resolve_config
  fi
  LAYERS=$(expand_layer_bundles "$LAYERS")

  exploit_disclaimer_gate "$PREV_LAYERS"

  BLACKARCH_CONSENT_GIVEN=0
  if [[ "$(any_layer_requires_blackarch "$LAYERS")" == "true" && "$DRY_RUN" != "1" ]]; then
    print_blackarch_warning
    if confirm "Add BlackArch and install those tools?" n; then
      BLACKARCH_CONSENT_GIVEN=1
    else
      echo -e "$CWR - Not adding BlackArch, so the security tools that need it are dropped from this install. Everything else carries on."
      LAYERS=$(strip_layers_matching "$LAYERS" _predicate_requires_blackarch)
    fi
  fi

  ISNVIDIA="$DETECTED_NVIDIA_PRESENT"
  ISAMD="$DETECTED_AMD_PRESENT"

  # Step 4 has to run before resolve_assistant (which would otherwise ask
  # its own question) and before the summary, since it feeds both.
  if [[ "$GUIDED" == "1" ]]; then
    guided_step_addons
    prompt_conflicting_packages
  fi

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

  local main_pkgs prep_pkgs base_main_pkgs base_prep_pkgs
  main_pkgs=$("$PYTHON_BIN" "$ROOT_DIR/lib/toml/merge.py" --base "$ROOT_DIR/profiles/base/$PROFILE.toml" --layers "$layer_args" --custom-apps "$ROOT_DIR/profiles/custom_apps.lst" --field main) || { echo -e "$CER - Failed to resolve package list (check --profile/--with values)"; exit 1; }
  prep_pkgs=$("$PYTHON_BIN" "$ROOT_DIR/lib/toml/merge.py" --base "$ROOT_DIR/profiles/base/$PROFILE.toml" --layers "$layer_args" --field prep) || { echo -e "$CER - Failed to resolve package list (check --profile/--with values)"; exit 1; }
  # The same two fields resolved from the base profile alone -- no layers,
  # no custom_apps.lst. That set is the shell itself, and a failure in it
  # still aborts; everything the merged lists add on top of it is an opt-in
  # extra whose failure is reported and skipped (install_package_list).
  base_main_pkgs=$("$PYTHON_BIN" "$ROOT_DIR/lib/toml/merge.py" --base "$ROOT_DIR/profiles/base/$PROFILE.toml" --field main) || { echo -e "$CER - Failed to resolve the base package list for $PROFILE"; exit 1; }
  base_prep_pkgs=$("$PYTHON_BIN" "$ROOT_DIR/lib/toml/merge.py" --base "$ROOT_DIR/profiles/base/$PROFILE.toml" --field prep) || { echo -e "$CER - Failed to resolve the base package list for $PROFILE"; exit 1; }

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "$CNT - [dry-run] plan:"
    echo "  profile: $PROFILE"
    echo "  layers: $LAYERS"
    echo "  nvidia: $ISNVIDIA"
    echo "  amd: $ISAMD"
    if [[ ",$LAYERS," == *",ai,"* ]]; then
      local dry_accel
      dry_accel=$(resolve_ollama_accel_package)
      echo "  ollama acceleration: ${dry_accel:-none (no NVIDIA/AMD GPU -- CPU inference)}"
    fi
    echo "  assistant: $ASSISTANT"
    echo "  greetd preview: $([[ "$GREETD_PREVIEW" == "1" ]] && echo "yes (scaffold only, not enabled)" || echo no)"
    if [[ "$ASSISTANT" == "true" ]]; then
      local dry_model
      dry_model=$(resolve_assistant_model_via_llmfit || true)
      if [[ -n "$dry_model" ]]; then
        echo "  would pull model: $dry_model [llmfit recommendation]"
      else
        echo "  would pull model: $ASSISTANT_FALLBACK_MODEL [fallback -- llmfit not installed yet]"
      fi
    fi
    echo "  would run: sudo pacman -Syu --noconfirm"
    echo "  prep packages:"
    print_package_plan "$prep_pkgs" "$base_prep_pkgs"
    echo "  main packages:"
    print_package_plan "$main_pkgs" "$base_main_pkgs"
    if [[ "$ISNVIDIA" == "true" ]]; then
      echo "  would install Nvidia driver: matching kernel headers + nvidia-open-dkms"
      echo "  would regenerate initramfs/UKI (mkinitcpio -P)"
    fi
    if [[ "$ISAMD" == "true" ]]; then
      echo "  would install AMD graphics userspace: mesa, vulkan-radeon, vulkan-icd-loader"
      if [[ "$(any_layer_requires_multilib "$LAYERS")" == "true" ]]; then
        echo "  would install 32-bit AMD Vulkan: lib32-mesa, lib32-vulkan-radeon"
      fi
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

  if [[ "$GUIDED" == "1" ]]; then
    guided_plan_and_confirm "$prep_pkgs" "$main_pkgs"
  else
    echo -e "$CNT - This script will run some commands that require sudo. You will be prompted to enter your password."
  fi

  print_stage 3 "System prep"
  check_conflicting_packages

  # Sync pacman DBs first: on a fresh/torn-down system /var/lib/pacman/sync/
  # is empty, and without it both base-devel and makepkg -si fail with
  # "database file for ... does not exist". This must precede yay's build.
  ensure_pacman_db

  ensure_base_devel

  echo -e "$CNT - Resolving AUR helper..."
  # `set -e` is off in the orchestrator, so a non-zero status from the command
  # substitution must be captured explicitly or a failed yay install (which
  # returns 1 from ensure_aur_helper) would silently leave AUR_HELPER empty.
  AUR_HELPER=""
  AUR_HELPER=$(ensure_aur_helper) || AUR_HELPER=""
  if [[ -z "$AUR_HELPER" ]]; then
    echo -e "$CWR - No AUR helper (yay/paru) is available on PATH. AUR packages will fail to resolve."
    echo -e "$CWR   Fix it manually: sudo pacman -S --needed base-devel git && git clone https://aur.archlinux.org/yay.git /tmp/yay && cd /tmp/yay && makepkg -si"
  else
    echo -e "$COK - Using AUR helper: $AUR_HELPER"
  fi

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
  # Sync + upgrade before installing anything new (issue #41): Arch mirrors
  # only ever carry the current package build, not the version that was
  # current when the local db was last refreshed -- installing against a
  # stale db can request a filename that's already been rotated off every
  # mirror, which pacman reports as a plain 404 per-mirror rather than
  # "your db is stale". `-Sy` alone is deliberately not used here: syncing
  # the db without upgrading already-installed packages is a partial
  # upgrade, which the Arch wiki calls out as unsupported and a real
  # source of broken dependencies for whatever gets installed next.
  # (No DRY_RUN branch here -- the dry-run plan above already exits before
  # Stage 5 is ever reached, see the upfront "[dry-run] plan" block.)
  echo -e "$CNT - Syncing package databases and upgrading the system..."
  sudo pacman -Syu --noconfirm &>> "$INSTLOG" || { echo -e "$CER - Failed to sync/upgrade the system package database. Re-run 'sudo pacman -Syu' by hand, resolve whatever it reports, then re-run install.sh."; exit 1; }

  install_package_list "$prep_pkgs" "$base_prep_pkgs"

  setup_nvidia
  setup_amd
  # Nvidia support has been built into the mainline "hyprland" package for a
  # while now; the "hyprland-nvidia" AUR package that used to carry the
  # patches is gone, so both paths install the same package.
  install_software hyprland

  install_package_list "$main_pkgs" "$base_main_pkgs"

  # After the main list, since the accelerated runner depends on the
  # `ollama` the ai layer installs, and before setup_assistant, which
  # pulls a model and wants the GPU runner already in place.
  setup_gpu_compute

  if [[ "$ASSISTANT" == "true" ]]; then
    setup_assistant || echo -e "$CWR - Aphotic Assistant setup did not finish; see $INSTLOG. The rest of the install continues."
  fi

  enable_core_services

  print_stage 6 "Deploying configs"
  # COPY_CONFIGS is "" (nobody has decided -- ask) or 1/0. The guided flow
  # sets it to 1 rather than asking: a desktop with none of its configs
  # deployed isn't a working install, so it belongs in the summary, not in
  # a prompt whose default was "no".
  CFG_COPIED=0
  local want_configs=0
  if [[ -n "$COPY_CONFIGS" ]]; then
    [[ "$COPY_CONFIGS" == "1" ]] && want_configs=1
  else
    echo -e "$CNT - Without Aphotic's config files you get Hyprland with none of Aphotic's desktop."
    echo -e "$CNT   Whatever is in ~/.config now was backed up in the previous step."
    if confirm "Install Aphotic's config files into ~/.config?" n; then
      want_configs=1
    fi
  fi

  if [[ "$want_configs" == "1" ]]; then
    CFG_COPIED=1
    deploy_user_configs
    setup_login_manager_theme
    if [[ "$GREETD_PREVIEW" == "1" ]]; then
      setup_greetd_greeter || echo -e "$CWR - greetd preview scaffold did not finish; see $INSTLOG. sddm is untouched either way."
    fi
    install_vscode_extensions
  fi

  print_stage 7 "Shell setup"
  activate_starship
  activate_zsh

  write_aphotic_toml "$APHOTIC_TOML" "$PROFILE" "$LAYERS" "$THEME" "$ISNVIDIA" "$AUR_HELPER" "$(date -Iseconds)" "$ISAMD"

  echo -e "\n\e[1;32m── Install summary ──\e[0m"
  echo -e "  Profile:       $PROFILE"
  echo -e "  Layers:        ${LAYERS:-none}"
  echo -e "  Theme:         $THEME"
  echo -e "  AUR helper:    $AUR_HELPER"
  echo -e "  Nvidia:        $ISNVIDIA"
  echo -e "  AMD:           $ISAMD"
  echo -e "  Assistant:     $ASSISTANT"
  echo -e "  Greetd preview: $([[ "$GREETD_PREVIEW" == "1" ]] && echo "deployed (run 'aphotic displaymanager status')" || echo no)"
  echo -e "  Configs copied: $([[ "$CFG_COPIED" == "1" ]] && echo yes || echo no)"
  echo -e "  Config saved:  $APHOTIC_TOML"
  if ((${#FAILED_OPTIONAL_PACKAGES[@]} > 0)); then
    echo -e "  Failed (optional): ${#FAILED_OPTIONAL_PACKAGES[@]} -- listed below"
  fi
  if [[ ",$LAYERS," == *",exploit-"* ]]; then
    echo -e "  Exploit disclaimer: $([[ -f "$EXPLOIT_ACK_FILE" ]] && echo "acknowledged, see $EXPLOIT_ACK_FILE" || echo "not recorded")"
  fi
  echo -e "$COK - Install complete."
  report_failed_optional_packages

  "$HOME/.local/bin/aphotic" whatsnew &>> "$INSTLOG" || true

  if [[ "$ISNVIDIA" == "true" ]]; then
    echo -e "$CAT - Since we attempted to setup an Nvidia GPU the script will now end and you should reboot."
    exit 0
  fi

  offer_start_hyprland
}

# Without this, Ctrl+C mid-install lands on whichever package is running
# and -- now that an optional failure is skipped rather than fatal -- the
# run would just walk on to the next package.
trap 'echo -e "\n$CWR - Interrupted -- stopping the install. Nothing further will be installed."; exit 130' INT
trap 'exit_code=$?; notice_exploit_failure "$exit_code"; exit "$exit_code"' EXIT

main "$@"
