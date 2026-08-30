#!/bin/bash
# install.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/lib/install/python.sh"
source "$ROOT_DIR/lib/install/aur.sh"
source "$ROOT_DIR/lib/install/multilib.sh"
source "$ROOT_DIR/lib/install/backup.sh"
source "$ROOT_DIR/lib/install/wizard.sh"
source "$ROOT_DIR/lib/install/blackarch.sh"
source "$ROOT_DIR/lib/install/exploit_disclaimer.sh"
source "$ROOT_DIR/lib/install/claude_hooks.sh"
source "$ROOT_DIR/lib/install/opencode_hooks.sh"
source "$ROOT_DIR/lib/install/codex_hooks.sh"
source "$ROOT_DIR/lib/install/assistant.sh"
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

# Layers are carried as a comma-separated string all the way through, so
# every gate needs the same exact-match test rather than a substring one --
# "ai" must not match "aichat" or "exploit-ai".
layer_selected() {
  local needle="$1" name
  IFS=',' read -ra _layer_list <<< "${LAYERS:-}"
  for name in "${_layer_list[@]:-}"; do
    [[ "$name" == "$needle" ]] && return 0
  done
  return 1
}
THEME=""
ASSISTANT=""
ACCEPT_EXPLOIT_DISCLAIMER=0
NVIDIA_DRIVER_ACTION=""

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

# Real, reported bug this guards against: a user with an already-working
# proprietary driver (nvidia/nvidia-dkms) ran install.sh and it blindly
# tried to install nvidia-open-dkms on top, with zero check for what was
# already there -- nvidia/nvidia-open (and their -dkms/-lts variants)
# provide overlapping files, so pacman/the AUR helper either refuses on
# a conflict or silently replaces a driver the user deliberately chose
# and had working. Covers every real variant: proprietary (nvidia,
# nvidia-lts, nvidia-dkms) and open (nvidia-open, nvidia-open-lts,
# nvidia-open-dkms).
detect_nvidia_driver_installed() {
  pacman -Qq 2>/dev/null | grep -qE '^nvidia(-open)?(-lts|-dkms)?$'
}

# Installs the actual Nvidia kernel driver (+ matching kernel headers) via
# DKMS. Nothing else in this script ever pulls in the driver itself -- the
# Nvidia block below this used to only edit mkinitcpio.conf/modprobe.d and
# assume a driver package would show up as a side dependency of something
# else, which it doesn't. That left `nvidia`/`nvidia_modeset`/etc. absent
# when mkinitcpio ran, so the initramfs/UKI was rebuilt with modules that
# didn't exist yet (silently -- mkinitcpio only warns, it doesn't fail the
# build) and the system fell back to no bound driver on the Nvidia GPU.
# nvidia-open-dkms targets Turing (RTX 20xx) and newer; pre-Turing cards
# need the proprietary nvidia-dkms package instead.
install_nvidia_driver() {
  if detect_nvidia_driver_installed; then
    local existing action="$NVIDIA_DRIVER_ACTION"
    existing="$(pacman -Qq 2>/dev/null | grep -E '^nvidia(-open)?(-lts|-dkms)?$' | paste -sd, -)"

    if [[ -z "$action" ]]; then
      if [[ -t 0 ]]; then
        echo -e "$CAT - An NVIDIA driver is already installed (${existing})."
        read -rep $'[\e[1;33mACTION\e[0m] - Keep it as-is, or uninstall it and let Aphotic install its recommended nvidia-open-dkms? (keep,reinstall) [keep] ' NV_CHOICE
        [[ "$NV_CHOICE" == "reinstall" ]] && action="reinstall" || action="keep"
      else
        # No TTY and no --nvidia-driver flag -- "should not fail for
        # users" means the safe default is to never touch a driver the
        # user already has working, not to guess.
        echo -e "$CWR - NVIDIA driver already installed (${existing}) and this is a non-interactive install with no --nvidia-driver flag -- defaulting to 'keep' (Aphotic will not touch it). Pass --nvidia-driver reinstall to opt into replacing it instead."
        action="keep"
      fi
    fi

    if [[ "$action" == "keep" ]]; then
      echo -e "$CNT - Keeping existing NVIDIA driver (${existing}) -- skipping Aphotic's own driver install."
      # nvidia-utils (nvidia-smi) is a separate userspace package, not a
      # driver -- doesn't conflict with proprietary or open, and the
      # Dashboard's Performance tab needs it regardless of which driver
      # variant the user is keeping, so still make sure it's present.
      if ! pacman -Qq nvidia-utils &>/dev/null; then
        install_software nvidia-utils
      fi
      return 0
    fi

    echo -e "$CNT - Uninstalling existing NVIDIA driver (${existing}) before installing Aphotic's recommended nvidia-open-dkms..."
    # shellcheck disable=SC2086
    "$AUR_HELPER" -R --noconfirm $(echo "$existing" | tr ',' ' ') &>> "$INSTLOG" || {
      echo -e "$CER - Failed to remove the existing driver (${existing}) -- see ${INSTLOG}. Not proceeding with a fresh install on top of a driver that wouldn't uninstall cleanly."
      return 1
    }
  fi

  echo -e "$CNT - Installing Nvidia driver..."
  local kernel_pkgs
  kernel_pkgs=$(pacman -Qq | grep -E '^linux(-lts|-zen|-hardened)?$' || true)
  if [[ -z "$kernel_pkgs" ]]; then
    echo -e "$CWR - Could not detect a linux/linux-lts/linux-zen/linux-hardened package; installing linux-headers as a best-effort fallback."
    kernel_pkgs="linux"
  fi
  while IFS= read -r kpkg; do
    [[ -n "$kpkg" ]] && install_software "${kpkg}-headers"
  done <<< "$kernel_pkgs"
  install_software nvidia-open-dkms
  # nvidia-utils provides nvidia-smi -- without it the Dashboard's
  # Performance tab has no way to read live NVIDIA GPU usage/temp and
  # silently shows "N/A" forever, since the driver package alone doesn't
  # carry the userspace query tools.
  install_software nvidia-utils
}

# Config-sync mode still needs to know the selected layers (the `ai` layer
# gates the Claude Code hook wiring in stage 6), but it must never prompt --
# the whole point of the flag is a non-interactive config refresh.
load_saved_config() {
  [[ -f "$APHOTIC_TOML" ]] || return 0
  LAYERS_KNOWN=1
  local saved_profile saved_layers saved_theme
  saved_profile=$("$PYTHON_BIN" -c '
import sys, tomllib
try:
    print(tomllib.load(open(sys.argv[1], "rb")).get("install", {}).get("profile", ""))
except Exception:
    print("")
' "$APHOTIC_TOML" 2>/dev/null)
  saved_layers=$("$PYTHON_BIN" -c '
import sys, tomllib
try:
    print(",".join(tomllib.load(open(sys.argv[1], "rb")).get("install", {}).get("layers", [])))
except Exception:
    print("")
' "$APHOTIC_TOML" 2>/dev/null)
  saved_theme=$("$PYTHON_BIN" -c '
import sys, tomllib
try:
    print(tomllib.load(open(sys.argv[1], "rb")).get("theme", {}).get("name", ""))
except Exception:
    print("")
' "$APHOTIC_TOML" 2>/dev/null)
  [[ -z "$PROFILE" ]] && PROFILE="$saved_profile"
  [[ -z "$LAYERS" ]] && LAYERS="$saved_layers"
  [[ -z "$THEME" ]] && THEME="$saved_theme"
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

# Everything a config refresh needs: the Configs/ copy, the symlinks that
# must track repo edits, the user systemd units, the Claude Code hook
# wiring, and PATH. Deliberately stops short of anything needing sudo
# (SDDM theme, wayland-sessions) so --config-only never asks for a
# password -- extracted rather than duplicated so the sync path and the
# full install can never drift apart.
deploy_user_configs() {
  echo -e "$CNT - Copying config files..."
  CUSTOM_LUA="$HOME/.config/hypr/custom.lua"
  CUSTOM_LUA_BACKUP=""
  if [[ -f "$CUSTOM_LUA" ]]; then
    CUSTOM_LUA_BACKUP=$(mktemp)
    cp "$CUSTOM_LUA" "$CUSTOM_LUA_BACKUP"
  fi

  cp -R "$ROOT_DIR/Configs/"* "$HOME/.config/"

  # A handful of paths under Configs/ need to track repo edits directly
  # rather than sit as the one-shot copy above -- a plain `cp -R` means
  # any later edit (bug fixes included) silently stops matching what's
  # actually live, with zero indication anything drifted, until a full
  # reinstall. Not hypothetical: this exact drift is what silently broke
  # SUPER+SHIFT+A (intelligence), SUPER+CTRL+SHIFT+B (bar cycle),
  # SUPER+SHIFT+D (dnd), and SUPER+N/SUPER+Y (keybinds.lua stale since
  # before those binds existed); kept regenerating Colours.qml from an
  # old wallust template (docs/IN_FLIGHT.md item 3); and left the
  # Kvantum theme selector pointed at the pre-rename "Noctis" name.
  # Symlinking these closes the whole bug class instead of patching it
  # path by path as each instance is separately noticed. ln -sfn (not
  # -sf) so re-running this on an existing install replaces a stale
  # symlink/copy in place instead of nesting one inside the other.
  #
  # Configs/hypr/* except three files that must stay real, independent
  # copies rather than track the repo:
  #   - custom.lua: the user's own local override (see the backup/
  #     restore immediately below), meant to diverge per-machine.
  #   - monitors.lua: hardware config (output name, exact resolution,
  #     position, scale) is inherently per-machine too -- the repo's own
  #     copy is only a generic "output='', mode=preferred" placeholder.
  #     Symlinking this one was a real regression, caught live: it threw
  #     away this machine's pinned "Virtual-1, 1920x1080" for the
  #     placeholder's "preferred", which negotiated down to 1280x800.
  #   - hyprland.lua: install.sh appends `require("nvidia")` to it below
  #     when Nvidia is detected -- a symlink would write that append
  #     straight into the tracked repo file instead of a local copy, and
  #     (since cp -R can no longer "reset" a symlinked target the way it
  #     resets a plain file) re-running install.sh would keep appending
  #     duplicate require lines with nothing ever clearing them.
  for entry in "$ROOT_DIR/Configs/hypr/"*; do
    name="$(basename "$entry")"
    case "$name" in
      custom.lua|monitors.lua|hyprland.lua) continue ;;
    esac
    rm -rf "$HOME/.config/hypr/$name"
    ln -sfn "$entry" "$HOME/.config/hypr/$name"
  done
  chmod +x "$HOME/.config/hypr/scripts/"*

  rm -rf "$HOME/.config/wallust"
  ln -sfn "$ROOT_DIR/Configs/wallust" "$HOME/.config/wallust"

  # Just the selector file -- Kvantum/Aphotic/Aphotic.kvconfig alongside
  # it is wallust template *output* (wallust.toml's `kvantum` entry), not
  # repo source, and must stay a real file wallust can keep overwriting.
  mkdir -p "$HOME/.config/Kvantum"
  rm -f "$HOME/.config/Kvantum/kvantum.kvconfig"
  ln -sfn "$ROOT_DIR/Configs/Kvantum/kvantum.kvconfig" "$HOME/.config/Kvantum/kvantum.kvconfig"

  if [[ -n "$CUSTOM_LUA_BACKUP" ]]; then
    cp "$CUSTOM_LUA_BACKUP" "$CUSTOM_LUA"
    rm -f "$CUSTOM_LUA_BACKUP"
    echo -e "$CNT - Preserved your existing hypr/custom.lua"
  fi

  mkdir -p "$HOME/.local/bin"
  ln -sf "$ROOT_DIR/Configs/.local/bin/aphotic" "$HOME/.local/bin/aphotic"

  echo -e "$CNT - Enabling the Aphotic shell restart-supervision unit..."
  mkdir -p "$HOME/.config/systemd/user"
  # Same symlink treatment as above -- these three unit files are only
  # ever added to or edited in the repo, never hand-written per machine,
  # so there's no user-owned-copy case to preserve the way custom.lua
  # has one. Concretely bit already: aphotic-agent-usage.service/.timer
  # postdated this machine's last cp -R and were never installed at all
  # (`systemctl --user is-enabled` reported "not-found"), so the Live
  # Agent Activity Module silently never ran.
  for unit in "$ROOT_DIR/Configs/systemd/user/"*; do
    ln -sfn "$unit" "$HOME/.config/systemd/user/$(basename "$unit")"
  done
  systemctl --user daemon-reload &>> "$INSTLOG"
  systemctl --user enable aphotic-shell.service &>> "$INSTLOG" || echo -e "$CWR - Could not enable aphotic-shell.service; the shell will still start via Hyprland's exec-once but won't auto-restart on crash."
  # A --config-only run on a clone that has never been installed has no saved
  # layer list, and "no layers" must not be read as "the user turned ai off" --
  # that would strip hooks and disable a timer nobody asked to remove.
  if [[ "$CONFIG_ONLY" == "1" && "$LAYERS_KNOWN" != "1" ]]; then
    echo -e "$CWR - No aphotic.toml found; leaving the agent usage timer and Claude Code hooks exactly as they are."
  elif layer_selected "ai"; then
    echo -e "$CNT - Enabling the agent usage-tracking timer..."
    systemctl --user enable --now aphotic-agent-usage.timer &>> "$INSTLOG" || echo -e "$CWR - Could not enable aphotic-agent-usage.timer; the bar's agent popout will show stale/no usage data until it's enabled manually."
  else
    echo -e "$CNT - AI layer not selected; leaving the agent usage-tracking timer off."
    systemctl --user disable --now aphotic-agent-usage.timer &>> "$INSTLOG" || true
  fi
  echo -e "$CNT - Enabling the SDDM background sync timer..."
  systemctl --user enable --now aphotic-sddm-sync.timer &>> "$INSTLOG" || echo -e "$CWR - Could not enable aphotic-sddm-sync.timer; the SDDM login background will only update via the per-theme-change best-effort call, not this periodic catch-up. Enable manually with 'systemctl --user enable --now aphotic-sddm-sync.timer'."
  # Writing hooks into someone's ~/.claude/settings.json is not something to
  # do to a user who never asked for the agent stack, so it follows the `ai`
  # layer -- and de-selecting that layer on a re-run removes what a previous
  # run added rather than leaving it behind.
  if [[ "$CONFIG_ONLY" == "1" && "$LAYERS_KNOWN" != "1" ]]; then
    :
  elif layer_selected "ai"; then
    echo -e "$CNT - Configuring the Claude Code hook for live agent session tracking..."
    if command -v jq >/dev/null 2>&1; then
      configure_claude_code_hooks "$ROOT_DIR/Configs/.local/lib/aphotic/agent_hook.sh" &>> "$INSTLOG" || echo -e "$CWR - Could not update ~/.claude/settings.json; the bar's agent popout will only show session presence/count, not live per-session status. Wire it manually — see docs/AGENT_TRACKING.md."
    else
      echo -e "$CWR - jq not found; skipping Claude Code hook setup. Wire it manually — see docs/AGENT_TRACKING.md."
    fi
  elif command -v jq >/dev/null 2>&1; then
    echo -e "$CNT - AI layer not selected; removing any Aphotic Claude Code hook entries..."
    remove_claude_code_hooks "$ROOT_DIR/Configs/.local/lib/aphotic/agent_hook.sh" &>> "$INSTLOG" || echo -e "$CWR - Could not clean ~/.claude/settings.json; remove the aphotic agent_hook.sh entries by hand if they are still there."
  fi

  # Same `ai`-layer opt-in as the Claude Code hook above, same
  # add-on-select/remove-on-deselect symmetry -- see lib/install/
  # opencode_hooks.sh for why this is a symlink into OpenCode's own plugin
  # auto-discovery directory rather than a settings.json merge.
  if [[ "$CONFIG_ONLY" == "1" && "$LAYERS_KNOWN" != "1" ]]; then
    :
  elif layer_selected "ai"; then
    echo -e "$CNT - Configuring the OpenCode hook for live agent session tracking..."
    configure_opencode_hook "$ROOT_DIR/Configs/.local/lib/aphotic/opencode_hook.js" &>> "$INSTLOG" || echo -e "$CWR - Could not symlink into ~/.config/opencode/plugins/; the bar's agent popout will only show session presence/count for OpenCode, not live per-session status. Wire it manually — see docs/AGENT_TRACKING.md."
  else
    echo -e "$CNT - AI layer not selected; removing the Aphotic OpenCode hook plugin..."
    remove_opencode_hook &>> "$INSTLOG" || echo -e "$CWR - Could not remove ~/.config/opencode/plugins/opencode_hook.js; remove it by hand if it's still there."
  fi

  # Same `ai`-layer opt-in as the Claude Code hook and the OpenCode plugin
  # above. Codex reads hooks from its own dedicated user-level hooks.json
  # (~/.codex/hooks.json, kept separate from config.toml on purpose), which
  # configure_codex_hooks upserts with jq exactly like claude_hooks.sh does
  # for ~/.claude/settings.json; codex_hook.sh translates Codex's wire
  # payload into the stdin shape agent_hook.py already expects and tags it
  # harness=codex. Codex only runs non-managed hooks once they're trusted
  # in-session (`/hooks`), so the post-install note tells the user to do
  # that once -- see lib/install/codex_hooks.sh and docs/AGENT_TRACKING.md.
  if [[ "$CONFIG_ONLY" == "1" && "$LAYERS_KNOWN" != "1" ]]; then
    :
  elif layer_selected "ai"; then
    echo -e "$CNT - Configuring the Codex hook for live agent session tracking..."
    if command -v jq >/dev/null 2>&1; then
      configure_codex_hooks "$ROOT_DIR/Configs/.local/lib/aphotic/codex_hook.sh" &>> "$INSTLOG" || echo -e "$CWR - Could not update ~/.codex/hooks.json; the bar's agent popout will only show session presence/count for Codex, not live per-session status. Wire it manually — see docs/AGENT_TRACKING.md."
      echo -e "$CWR - Codex hooks are written, but Codex only runs hooks it trusts: start codex once, open /hooks, and trust the Aphotic entries (or pass --dangerously-bypass-hook-trust to a single invocation). See docs/AGENT_TRACKING.md."
    else
      echo -e "$CWR - jq not found; skipping Codex hook setup. Wire it manually — see docs/AGENT_TRACKING.md."
    fi
  elif command -v jq >/dev/null 2>&1; then
    echo -e "$CNT - AI layer not selected; removing any Aphotic Codex hook entries..."
    remove_codex_hooks "$ROOT_DIR/Configs/.local/lib/aphotic/codex_hook.sh" &>> "$INSTLOG" || echo -e "$CWR - Could not clean ~/.codex/hooks.json; remove the aphotic codex_hook.sh entries by hand if they are still there."
  fi

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
}

config_sync() {
  TOTAL_STAGES=3
  print_stage 1 "Backup"
  if [[ "$NO_BACKUP" != "1" ]]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    echo -e "$CNT - Snapshotting existing configs..."
    mapfile -t CONFIG_DIRS < <(find "$ROOT_DIR/Configs" -maxdepth 1 -mindepth 1 -not -name '.*' -exec basename {} \;)
    snapshot_config "$TIMESTAMP" "${CONFIG_DIRS[@]}"
    prune_backups "$KEEP_BACKUPS"
    echo -e "$COK - Backup saved under $(backup_root)/$TIMESTAMP"
  else
    echo -e "$CWR - Skipping backup (--no-backup)."
  fi

  print_stage 2 "Syncing configs"
  deploy_user_configs

  print_stage 3 "Restarting the shell"
  if systemctl --user is-enabled aphotic-shell.service &>/dev/null; then
    systemctl --user restart aphotic-shell.service &>> "$INSTLOG" && echo -e "$COK - Restarted aphotic-shell.service." || echo -e "$CWR - Could not restart aphotic-shell.service; restart Quickshell manually (SUPER+B)."
  else
    echo -e "$CNT - aphotic-shell.service isn't enabled; restart Quickshell manually (SUPER+B) to pick up the new config."
  fi

  echo -e "\n\e[1;32m── Config sync summary ──\e[0m"
  echo -e "  Layers:        ${LAYERS:-none}"
  echo -e "  Configs:       copied from $ROOT_DIR/Configs"
  echo -e "  Packages:      untouched"
  echo -e "  aphotic.toml:  left as-is"
  echo -e "$COK - Config sync complete."

  "$HOME/.local/bin/aphotic" whatsnew &>> "$INSTLOG" || true
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

  if [[ "$CONFIG_ONLY" == "1" ]]; then
    load_saved_config
    LAYERS=$(expand_layer_bundles "$LAYERS")
    echo -e "$CNT - Config-sync mode: reusing saved config (profile=${PROFILE:-unset}, layers=${LAYERS:-none}). No packages will be installed."
    config_sync
    exit 0
  fi

  print_stage 2 "Configuration"

  PREV_LAYERS=""
  if [[ -f "$APHOTIC_TOML" ]]; then
    PREV_LAYERS=$("$PYTHON_BIN" -c '
import sys, tomllib
try:
    d = tomllib.load(open(sys.argv[1], "rb"))
    print(",".join(d.get("install", {}).get("layers", [])))
except Exception:
    print("")
' "$APHOTIC_TOML" 2>/dev/null || echo "")
  fi

  resolve_config
  LAYERS=$(expand_layer_bundles "$LAYERS")

  exploit_disclaimer_gate "$PREV_LAYERS"

  if [[ "$(any_layer_requires_blackarch "$LAYERS")" == "true" && "$DRY_RUN" != "1" ]]; then
    print_blackarch_warning
    read -rep $'[\e[1;33mACTION\e[0m] - Continue enabling BlackArch for the exploit-* layers that need it? (y,N) ' EXPLOIT_OK
    if [[ "$EXPLOIT_OK" != "y" && "$EXPLOIT_OK" != "Y" ]]; then
      echo -e "$CWR - Skipping the BlackArch-backed exploit-* layers."
      LAYERS=$(strip_layers_matching "$LAYERS" _predicate_requires_blackarch)
    fi
  fi

  ISNVIDIA=$(detect_nvidia)
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
  # Sync + upgrade before installing anything new (issue #41): Arch mirrors
  # only ever carry the current package build, not the version that was
  # current when the local db was last refreshed -- installing against a
  # stale db can request a filename that's already been rotated off every
  # mirror, which pacman reports as a plain 404 per-mirror rather than
  # "your db is stale". `-Sy` alone is deliberately not used here: syncing
  # the db without upgrading already-installed packages is a partial
  # upgrade, which the Arch wiki calls out as unsupported and a real
  # source of broken dependencies for whatever gets installed next.
  echo -e "$CNT - Syncing package databases and upgrading the system..."
  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "$CNT - [dry-run] would run: sudo pacman -Syu --noconfirm"
  else
    sudo pacman -Syu --noconfirm &>> "$INSTLOG" || { echo -e "$CER - Failed to sync/upgrade the system package database. Re-run 'sudo pacman -Syu' by hand, resolve whatever it reports, then re-run install.sh."; exit 1; }
  fi

  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && install_software "$pkg"
  done <<< "$prep_pkgs"

  if [[ "$ISNVIDIA" == "true" ]]; then
    install_nvidia_driver
    echo -e "$CNT - Configuring Nvidia modules..."
    sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    if ! sudo grep -qF "options nvidia-drm modeset=1" /etc/modprobe.d/nvidia.conf 2>/dev/null; then
      echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf &>> "$INSTLOG"
    fi
    # -P (process every preset's configured targets) instead of a
    # hand-picked /boot/initramfs-custom.img: on a UKI setup (systemd-boot
    # with default_uki=.../arch-linux.efi and no default_image, which is
    # what a stock Arch systemd-boot install gives you) a custom image path
    # is never referenced by any boot entry, so the actual bootable
    # image/UKI never picks up the Nvidia modules regardless of whether the
    # driver package installed correctly.
    echo -e "$CNT - Regenerating initramfs/UKI..."
    sudo mkinitcpio -P &>> "$INSTLOG" || echo -e "$CWR - mkinitcpio failed to rebuild the initramfs/UKI; check $INSTLOG, then run 'sudo mkinitcpio -P' manually before rebooting."
  fi
  # Nvidia support has been built into the mainline "hyprland" package for a
  # while now; the "hyprland-nvidia" AUR package that used to carry the
  # patches is gone, so both paths install the same package.
  install_software hyprland

  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && install_software "$pkg"
  done <<< "$main_pkgs"

  if [[ "$ASSISTANT" == "true" ]]; then
    setup_assistant || echo -e "$CWR - Aphotic Assistant setup did not finish; see $INSTLOG. The rest of the install continues."
  fi

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
    deploy_user_configs

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

  read -rep $'[\e[1;33mACTION\e[0m] - Download the larger community wallpaper pool now? ~145MB across all 8 themes; each theme already ships a handful of wallpapers regardless, this just adds more choice. Skip if you\'re on a slow connection (y,N) ' EXTRA_WALLPAPERS
  if [[ "$EXTRA_WALLPAPERS" == "Y" || "$EXTRA_WALLPAPERS" == "y" ]]; then
    "$HOME/.local/bin/aphotic" wallpaper --fetch-extra -y || echo -e "$CWR - Could not fetch extra wallpapers now; run 'aphotic wallpaper --fetch-extra' any time later."
  else
    echo -e "$CNT - Skipping the extra wallpaper pool. Run 'aphotic wallpaper --fetch-extra' any time later to get it."
  fi

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

  read -rep $'[\e[1;33mACTION\e[0m] - Would you like to start Hyprland now? (y,n) ' HYP
  if [[ "$HYP" == "Y" || "$HYP" == "y" ]]; then
    exec sudo systemctl start sddm &>> "$INSTLOG"
  fi
}

trap 'exit_code=$?; notice_exploit_failure "$exit_code"; exit "$exit_code"' EXIT

main "$@"
