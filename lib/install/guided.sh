#!/usr/bin/env bash
# lib/install/guided.sh
set -euo pipefail

# The prompt-driven path, for someone installing Aphotic on Arch for the
# first time.
#
# Only runs when install.sh was invoked with no options at all and stdin is
# a TTY (install.sh's GUIDED gate). Every flag-driven path is untouched:
# --profile/--with/--theme/--opt-in/--dry-run/--config-only/
# --strip-conflicts/--keep-conflicts/--accept-exploit-disclaimer, CI, and
# curl-piped installs all keep taking the same zero-prompt or flag-resolved
# route they always did.
#
# What this replaces: twelve confirm() prompts spread across install.sh and
# six lib/install modules, each firing wherever the script happened to
# reach it -- so a first install interleaved layer questions with NVIDIA
# driver questions, BlackArch questions and shell-activation questions as
# unrelated interruptions, several of them after the install had already
# started changing the system. Here they are one ordered conversation:
# numbered steps, the two consequential questions (NVIDIA driver
# replacement, BlackArch) left standalone where they can't be skimmed
# past, and a single summary to accept before anything is touched.

GUIDED_STEP=0
GUIDED_STEPS=4

_guided_heading() {
  echo -e "\n\e[1;36m── $1 ──\e[0m"
}

_guided_step() {
  GUIDED_STEP=$((GUIDED_STEP + 1))
  _guided_heading "Step $GUIDED_STEP of $GUIDED_STEPS: $1"
}

# "${arr[*]}" with IFS=", " joins on the first IFS character only, i.e.
# a bare comma -- so build the list by hand.
_guided_join() {
  local out="" item
  for item in "$@"; do
    out="${out:+$out, }$item"
  done
  echo "$out"
}

_guided_profile_label() {
  case "$1" in
    minimal) echo "just the desktop (Aphotic and Hyprland only)" ;;
    full) echo "full desktop (Aphotic plus browser, files, media, fonts)" ;;
    *) echo "${1:-unknown}" ;;
  esac
}

# Plain-language gloss for the plan summary -- the layer names themselves
# are what aphotic.toml records and what --with takes, so they stay
# visible, just no longer on their own.
_guided_layer_label() {
  case "$1" in
    gaming) echo "gaming -- Steam, GameMode, MangoHud" ;;
    dev) echo "development -- Neovim, tmux, fzf, ripgrep, lazygit, GitHub CLI" ;;
    ai) echo "AI features -- Ollama, agent graph, AI chat, Claude Code" ;;
    exploit-recon) echo "security: recon -- nmap, amass, subfinder, theHarvester" ;;
    exploit-web) echo "security: web testing -- Burp Suite CE, sqlmap, ffuf, ZAP" ;;
    exploit-network) echo "security: network -- Wireshark, aircrack-ng, bettercap" ;;
    exploit-passwords) echo "security: passwords -- John the Ripper, hashcat, Hydra" ;;
    exploit-wordlists) echo "security: rockyou wordlist (~130MB)" ;;
    exploit-reversing) echo "security: reverse engineering -- Ghidra, radare2, gdb" ;;
    exploit-forensics) echo "security: forensics -- Autopsy, Sleuth Kit, Volatility 3" ;;
    exploit-reporting) echo "security: report writing -- aphotic report, pandoc" ;;
    *) echo "$1" ;;
  esac
}

guided_intro() {
  _guided_heading "Guided setup"
  cat <<'EOF'

This installer turns a working Arch Linux system into the Aphotic desktop:
a bar, an app launcher, notifications, a lock screen and a settings panel,
all running on the Hyprland window manager.

A few questions, then a summary of everything that is about to happen.
Nothing is installed and nothing in your home folder is changed until you
say yes at that summary. Press Enter at any question to take the default
shown in brackets.

Accepting every default gets you:

  Software    The full desktop -- Aphotic plus a browser, file manager,
              terminal, media player, fonts and audio support.
  Extras      None. The gaming, development, AI and security tool sets are
              all optional, and any of them can be added later by running
              this installer again.
  Look        The "tokyonight" colour theme. Switchable at any time with
              'aphotic theme set <name>'.
  Graphics    If a graphics driver is already installed, it is left alone.
  Your files  Everything currently in ~/.config is copied to a dated
              backup folder before Aphotic's own config files are written.

EOF
}

# Steps 1-3: what to install, which optional tool sets, and which theme.
# Reuses wizard.sh's prompt_profile/prompt_layers/prompt_theme -- the same
# pickers --opt-in has always used, not a second set.
guided_configure() {
  local reused=0

  if [[ "$DETECTED_APHOTIC_INSTALL" == "1" ]]; then
    echo -e "\n$CNT - Aphotic is already installed on this machine: $(_guided_profile_label "$DETECTED_APHOTIC_PROFILE"), extras: ${DETECTED_APHOTIC_LAYERS:-none}."
    if confirm "Install it again with those same choices?" y; then
      PROFILE="$DETECTED_APHOTIC_PROFILE"
      LAYERS="$DETECTED_APHOTIC_LAYERS"
      reused=1
      GUIDED_STEPS=2
      echo -e "$CNT - Keeping that software selection; you will still be asked about the theme and the optional add-ons."
    fi
  fi

  if [[ "$reused" != "1" ]]; then
    _guided_step "how much software?"
    echo ""
    PROFILE=$(prompt_profile)

    _guided_step "optional extra tool sets"
    cat <<'EOF'

Aphotic is a complete desktop without any of these. Each one is a set of
programs for a particular kind of work, and any of them can be added later
by running this installer again.

EOF
    # Default preset 2 (none) rather than --opt-in's cherry-pick default:
    # someone who typed no flags at all asked to be walked through, not to
    # be handed ten follow-up questions for pressing Enter.
    LAYERS=$(prompt_layers 2)
  fi

  _guided_step "how it looks"
  echo ""
  THEME=$(prompt_theme)
}

# Step 4: every remaining optional extra in one list, replacing the five
# separate prompts these used to be (assistant, wallpaper pool, starship,
# zsh) -- each of which used to fire at a different point in the run, two
# of them after packages had already been installed.
#
# Purely additive: nothing here is on unless its number is typed, so
# "press Enter" is always the do-nothing answer. Sets the same globals the
# flags set, which is why the stage functions themselves need no idea this
# flow exists.
guided_step_addons() {
  _guided_step "optional add-ons"

  local -a keys=() lines=()
  local n=0

  if [[ "$DETECTED_NVIDIA_PRESENT" == "true" ]]; then
    local recommend=""
    layer_selected ai && recommend="   (recommended -- you chose the AI extras)"
    n=$((n + 1)); keys+=("assistant")
    lines+=("  $n) Aphotic Assistant$recommend
     A chatbot that runs entirely on this machine and can answer questions
     about your desktop. Downloads a language model of a few GB, and needs
     an NVIDIA graphics card (this machine has one). Switching it on also
     turns on the AI extras it runs from.")
  fi

  n=$((n + 1)); keys+=("wallpapers")
  lines+=("  $n) Community wallpaper pack
     About 145MB of extra wallpapers. Every theme already comes with its
     own, so this only adds more to choose from.")

  n=$((n + 1)); keys+=("starship")
  lines+=("  $n) A better terminal prompt (starship)
     Shows the folder you are in, the git branch and similar, in place of
     the plain bash prompt. Adds one line to ~/.bashrc.")

  n=$((n + 1)); keys+=("zsh")
  lines+=("  $n) Use zsh as your shell instead of bash
     Copies Aphotic's zsh setup and changes your login shell with 'chsh'.
     Leave this off unless you already know you want zsh.")

  cat <<'EOF'

None of these are required, and each can also be turned on later.

EOF
  local line
  for line in "${lines[@]}"; do
    echo "$line"
    echo ""
  done

  local -a picked=()
  local i
  for ((i = 0; i < ${#keys[@]}; i++)); do
    picked+=(0)
  done

  local answer tok idx
  local -a tokens=()
  echo "Type the numbers of any you want, separated by spaces, or press Enter for none."
  answer=$(prompt_text "Which add-ons? (e.g. \"1 3\", or Enter for none)")
  read -ra tokens <<< "$answer" || true
  for tok in ${tokens[@]+"${tokens[@]}"}; do
    if ! [[ "$tok" =~ ^[0-9]+$ ]]; then
      echo -e "$CWR - Ignoring \"$tok\" -- expected a number from the list."
      continue
    fi
    idx=$((tok))
    if (( idx < 1 || idx > ${#keys[@]} )); then
      echo -e "$CWR - Ignoring \"$tok\" -- there is no add-on with that number."
      continue
    fi
    picked[$((idx - 1))]=1
  done

  ASSISTANT="false"
  EXTRA_WALLPAPERS=0
  ACTIVATE_STARSHIP=0
  ACTIVATE_ZSH=0

  local -a chosen=()
  for ((i = 0; i < ${#keys[@]}; i++)); do
    [[ "${picked[$i]}" == "1" ]] || continue
    case "${keys[$i]}" in
      assistant) ASSISTANT="true"; chosen+=("Aphotic Assistant") ;;
      wallpapers) EXTRA_WALLPAPERS=1; chosen+=("community wallpaper pack") ;;
      starship) ACTIVATE_STARSHIP=1; chosen+=("starship prompt") ;;
      zsh) ACTIVATE_ZSH=1; chosen+=("zsh as your shell") ;;
    esac
  done

  # Configs are not an add-on: a desktop with no config files deployed is
  # not a working install, so the guided path decides this rather than
  # asking (install.sh's own "copy config files?" prompt, which defaulted
  # to no, is still there for flag-driven runs).
  COPY_CONFIGS=1

  if [[ ${#chosen[@]} -eq 0 ]]; then
    echo -e "$CNT - No add-ons selected."
  else
    echo -e "$CNT - Add-ons: $(_guided_join "${chosen[@]}")"
  fi
}

# The one place a guided install can still say no. Everything above this
# point has only recorded answers; the first change to the system happens
# after it.
guided_plan_and_confirm() {
  local prep_pkgs="$1" main_pkgs="$2"
  local prep_count main_count total _plan_layers

  prep_count=$(grep -c . <<< "$prep_pkgs" || true)
  main_count=$(grep -c . <<< "$main_pkgs" || true)
  total=$((prep_count + main_count))

  _guided_heading "Ready to install"
  echo ""
  printf '  %-16s %s\n' "Software" "$(_guided_profile_label "$PROFILE")"

  if [[ -z "$LAYERS" ]]; then
    printf '  %-16s %s\n' "Extra tool sets" "none"
  else
    local first=1 name
    IFS=',' read -ra _plan_layers <<< "$LAYERS" || true
    for name in "${_plan_layers[@]}"; do
      if [[ "$first" == "1" ]]; then
        printf '  %-16s %s\n' "Extra tool sets" "$(_guided_layer_label "$name")"
        first=0
      else
        printf '  %-16s %s\n' "" "$(_guided_layer_label "$name")"
      fi
    done
  fi

  printf '  %-16s %s\n' "Theme" "$THEME"

  local addons=()
  [[ "$ASSISTANT" == "true" ]] && addons+=("Aphotic Assistant")
  [[ "${EXTRA_WALLPAPERS:-0}" == "1" ]] && addons+=("community wallpaper pack")
  [[ "${ACTIVATE_STARSHIP:-0}" == "1" ]] && addons+=("starship prompt")
  [[ "${ACTIVATE_ZSH:-0}" == "1" ]] && addons+=("zsh as your login shell")
  if [[ ${#addons[@]} -eq 0 ]]; then
    printf '  %-16s %s\n' "Add-ons" "none"
  else
    printf '  %-16s %s\n' "Add-ons" "$(_guided_join "${addons[@]}")"
  fi

  if [[ "$DETECTED_NVIDIA_PRESENT" == "true" ]]; then
    if [[ -n "$DETECTED_NVIDIA_DRIVER" ]]; then
      if [[ "$NVIDIA_DRIVER_ACTION" == "reinstall" ]]; then
        printf '  %-16s %s\n' "Graphics" "replacing $DETECTED_NVIDIA_DRIVER with nvidia-open-dkms"
      else
        printf '  %-16s %s\n' "Graphics" "keeping the NVIDIA driver you already have ($DETECTED_NVIDIA_DRIVER)"
      fi
    else
      printf '  %-16s %s\n' "Graphics" "installing the NVIDIA driver (nvidia-open-dkms) for your card"
    fi
  fi

  printf '  %-16s %s\n' "Packages" "$total to install, after a full system update (pacman -Syu)"
  if [[ "$NO_BACKUP" == "1" ]]; then
    printf '  %-16s %s\n' "Your configs" "NOT backed up (--no-backup), then overwritten by Aphotic's"
  else
    printf '  %-16s %s\n' "Your configs" "~/.config copied to $(backup_root)/<date>, then Aphotic's copied in"
  fi
  [[ "$PROFILE" == "full" ]] && printf '  %-16s %s\n' "Login screen" "SDDM enabled and themed, so you can pick Hyprland at login"
  printf '  %-16s %s\n' "Password" "some steps need sudo -- you will be asked for yours"
  echo ""
  echo "This takes a while: it builds AUR packages, and on a slow connection"
  echo "the downloads dominate. Progress and errors are logged to $INSTLOG."
  echo ""

  if confirm "Start the install now?" y; then
    return 0
  fi

  echo -e "$CNT - Stopped. No packages were installed and nothing in your home folder was changed."
  echo -e "$CNT - Run ./install.sh again whenever you want to go through this."
  exit 0
}
