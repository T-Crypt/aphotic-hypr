#!/usr/bin/env bash
set -euo pipefail

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


# Every question below is worded for someone whose first Arch install this
# is: no bare layer names, no "AUR"/"multilib"/"repo" without a line of
# context, and the concrete programs each choice installs spelled out. The
# order and number of reads is load-bearing -- tests/test_wizard.sh drives
# these by feeding positional answers, and the guided flow reuses them
# rather than carrying a second copy.

prompt_profile() {
  local answer
  cat >&2 <<'EOF'
  1) Full desktop  (recommended)
     Everything a day-to-day machine needs: the Aphotic desktop plus
     Firefox, a file manager, a terminal, an image and video player,
     fonts, Bluetooth and audio support.

  2) Just the desktop
     Only what Aphotic itself needs to run. No browser, no media player,
     no fonts beyond the ones the desktop uses -- you install the
     programs you want yourself afterwards.

EOF
  read -rp "Your choice? [1-2, default 1 - full desktop]: " answer
  case "$answer" in
    2|minimal) echo "minimal" ;;
    *) echo "full" ;;
  esac
}

# prompt_layers [default-preset] -- default-preset is which option an empty
# answer takes (3, cherry-pick, for --opt-in; the guided flow passes 2, so
# pressing Enter through a first install adds nothing).
prompt_layers() {
  local default_preset="${1:-3}"
  local layers=()
  local answer

  # Presets are a shortcut over the same questions below -- not a second
  # mechanism. "One by one" is just answering them.
  echo "Optional extra tool sets:" >&2
  echo "  1) All of them      -- gaming, development, AI and security tools" >&2
  echo "  2) None             -- just the desktop; add any of these later" >&2
  echo "  3) Choose one by one" >&2
  read -rp "Your choice? [1-3, default $default_preset]: " answer
  answer="${answer:-$default_preset}"
  case "$answer" in
    1)
      echo "gaming,dev,ai,exploit"
      return 0
      ;;
    2)
      echo ""
      return 0
      ;;
  esac

  cat >&2 <<'EOF'

  Gaming
    Steam, plus GameMode and MangoHud -- one tunes the system while a game
    is running, the other shows framerate and temperatures on screen. This
    also switches on "multilib", an official Arch package collection that
    is off by default and carries the 32-bit libraries many games need.
EOF
  read -rp "  Install the gaming tools? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] && layers+=("gaming")

  cat >&2 <<'EOF'

  Development
    Neovim, tmux, fzf, ripgrep, fd, lazygit and the GitHub command line --
    a terminal-based coding setup. Adding these does not change any editor
    or shell you already use.
EOF
  read -rp "  Install the development tools? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] && layers+=("dev")

  # Say what this actually does before asking: it is the only choice here
  # that writes into a config file outside this project's own files
  # (~/.claude/settings.json).
  cat >&2 <<'EOF'

  AI features
    Ollama, which runs language models locally on this machine, plus
    Aphotic's agent graph, AI chat panel and live Claude Code session
    tracking. This is the only choice here that writes outside Aphotic's
    own files: it adds hooks to ~/.claude/settings.json and switches on a
    timer that records how much you use those tools. What it records stays
    in your home folder.
EOF
  read -rp "  Install the AI features? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] && layers+=("ai")

  cat >&2 <<'EOF'

  Security / penetration-testing tools
    Scanners and testing tools for networks, websites and files. Most of
    them are not in Arch's own package collections and come from BlackArch
    instead: a large third-party collection that moves fast and breaks
    more often than Arch's. You will be asked separately before it is
    added, and asked to agree that you will only use these tools on
    systems you own or have written permission to test.
EOF
  read -rp "  Install security tools? [y/N]: " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "    The usual starting set is recon + web + network." >&2
    read -rp "    Use that starting set? [Y/n]: " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
      layers+=("exploit")
    else
      read -rp "    Recon -- finds hosts, subdomains and open ports (nmap, amass, subfinder, theHarvester, recon-ng)? [y/N]: " answer
      [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-recon")

      read -rp "    Web -- tests websites and web apps (Burp Suite CE, sqlmap, ffuf, gobuster, nikto, ZAP)? [y/N]: " answer
      [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-web")

      read -rp "    Network -- captures and inspects network traffic (Wireshark, aircrack-ng, bettercap, tcpdump)? [y/N]: " answer
      [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-network")
    fi

    read -rp "    Passwords -- tries to recover passwords from stored hashes (John the Ripper, hashcat, Hydra)? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      layers+=("exploit-passwords")
      read -rp "      Also download the rockyou list of common passwords? ~130MB, from the OWASP SecLists project -- always a separate choice, never included on its own [y/N]: " answer
      [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-wordlists")
    fi

    read -rp "    Reverse engineering -- takes compiled programs apart to see what they do (Ghidra, radare2, Cutter, gdb + pwndbg, binwalk)? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-reversing")

    read -rp "    Digital forensics -- examines disk images and memory dumps (Autopsy, Sleuth Kit, Volatility 3)? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-forensics")

    read -rp "    Report writing -- templates and an 'aphotic report' command for writing up findings? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-reporting")
  fi

  local IFS=","
  echo "${layers[*]}"
}

# Reads [theme].display_name out of a theme.toml -- deliberately a
# purpose-built grep/awk pass rather than pulling in aphotic_toml_get
# from globalcontrol.sh (not sourced here, and this install-time-only
# read doesn't need the shared shell's full TOML helper).
_wizard_theme_display_name() {
  local toml="$1"
  [[ -f "$toml" ]] || return 0
  awk '
    /^\[theme\]/ { insec=1; next }
    /^\[/ { insec=0 }
    insec && /^display_name[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "");
      gsub(/^"|"$/, "");
      print;
      exit
    }
  ' "$toml"
}

# Themes live as directories under Configs/awww/ (see
# themes/THEME_SPEC.md) -- computed from this script's own path rather
# than a global like ROOT_DIR so this stays callable in isolation (tests
# source wizard.sh directly without setting ROOT_DIR).
_wizard_repo_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

prompt_theme() {
  local repo_dir names=() labels=() dir name label answer default_idx=1 i

  repo_dir="$(_wizard_repo_dir)"
  for dir in "$repo_dir"/Configs/awww/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    label="$(_wizard_theme_display_name "${dir}theme.toml")"
    names+=("$name")
    labels+=("${label:-$name}")
  done

  if [[ ${#names[@]} -eq 0 ]]; then
    # No theme folders found (shouldn't happen in a real clone) -- fall
    # back to a name rather than leaving THEME empty, since downstream
    # `aphotic theme set` treats an unresolvable name as an error, not a
    # silent no-op.
    echo "tokyonight"
    return 0
  fi

  for i in "${!names[@]}"; do
    [[ "${names[$i]}" == "tokyonight" ]] && default_idx=$((i + 1))
  done

  echo "Colours. Each theme restyles the whole desktop -- bar, menus," >&2
  echo "notifications and wallpapers. You can change it at any time" >&2
  echo "afterwards with 'aphotic theme set <name>'." >&2
  echo "" >&2
  for i in "${!names[@]}"; do
    printf '  %d) %-12s %s\n' "$((i + 1))" "${names[$i]}" "${labels[$i]}" >&2
  done
  read -rp "Your choice? [1-${#names[@]}, default ${default_idx} - ${names[$((default_idx - 1))]}]: " answer
  answer="${answer:-$default_idx}"

  if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#names[@]} )); then
    echo "${names[$((answer - 1))]}"
  else
    echo -e "$CWR - That isn't one of the numbers listed, using ${names[$((default_idx - 1))]}." >&2
    echo "${names[$((default_idx - 1))]}"
  fi
}

# Reads aphotic.toml's [install].layers as a CSV, or "" if the file/key is
# missing. Shared by load_saved_config() and main()'s previous-layers
# lookup for the exploit-disclaimer re-acknowledgment diff, so the two
# don't carry their own slightly-different copies of the same tomllib call.
read_saved_layers() {
  local toml="$1"
  [[ -f "$toml" ]] || { echo ""; return 0; }
  "$PYTHON_BIN" -c '
import sys, tomllib
try:
    d = tomllib.load(open(sys.argv[1], "rb"))
    print(",".join(d.get("install", {}).get("layers", [])))
except Exception:
    print("")
' "$toml" 2>/dev/null || echo ""
}

# Config-sync mode still needs to know the selected layers (the `ai` layer
# gates the Claude Code hook wiring in config_deploy.sh), but it must never
# prompt -- the whole point of the flag is a non-interactive config
# refresh.
load_saved_config() {
  [[ -f "$APHOTIC_TOML" ]] || return 0
  LAYERS_KNOWN=1
  local saved_profile saved_theme
  saved_profile=$("$PYTHON_BIN" -c '
import sys, tomllib
try:
    print(tomllib.load(open(sys.argv[1], "rb")).get("install", {}).get("profile", ""))
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
  [[ -z "$LAYERS" ]] && LAYERS="$(read_saved_layers "$APHOTIC_TOML")"
  [[ -z "$THEME" ]] && THEME="$saved_theme"
}

# Resolves PROFILE/LAYERS/THEME for a flag-driven (non---config-only)
# install -- the guided path takes guided_configure() in
# lib/install/guided.sh instead, and never reaches this function.
#
# Default here, with none of --profile/--with/--opt-in passed, is still
# the zero-prompt "daily driver" path -- full profile, no optional layers.
# That is what a piped/no-TTY install gets (a bare `./install.sh` on a
# terminal now gets the guided flow instead), and --opt-in still restores
# the cherry-pick pickers above for anyone who wants only those; any of
# --profile/--with/--theme passed directly always wins over both.
#
# This is a deliberate judgment call, not a mechanical default: real
# layer packages still only install via this terminal flow today (no
# other mechanism exists yet), so the pickers aren't going away, just no
# longer imposed on every fresh install by default.
resolve_config() {
  # Reuses detect.sh's already-computed findings (stage 1) rather than
  # re-querying aphotic.toml here -- the whole point of a consolidated
  # detection pass is that later stages consume it instead of repeating it.
  if [[ "$DETECTED_APHOTIC_INSTALL" == "1" && -z "$PROFILE" && -z "$LAYERS" ]]; then
    echo -e "$CNT - Aphotic is already installed here (profile=$DETECTED_APHOTIC_PROFILE, extras=${DETECTED_APHOTIC_LAYERS:-none})."
    if [[ -t 0 ]]; then
      if confirm "Install it again with those same choices?" y; then
        PROFILE="$DETECTED_APHOTIC_PROFILE"
        LAYERS="$DETECTED_APHOTIC_LAYERS"
      fi
    else
      # No TTY to ask -- reuse rather than silently fall through to the
      # zero-prompt daily-driver default below, which would quietly drop
      # whatever layers a previous run had already selected.
      echo -e "$CNT - Non-interactive install with an existing config and no --profile/--with -- reusing it."
      PROFILE="$DETECTED_APHOTIC_PROFILE"
      LAYERS="$DETECTED_APHOTIC_LAYERS"
    fi
  fi

  if [[ -z "$PROFILE" && -z "$LAYERS" && "$OPT_IN" != "1" ]]; then
    echo -e "$CNT - No --profile/--with/--opt-in given -- installing the daily-driver setup (full profile, no optional layers: gaming/dev/ai/exploit)."
    echo -e "$CNT - Run ./install.sh with no options at all for the guided setup, --opt-in for just the layer picker, or --with gaming,dev,ai,exploit to pick layers directly. Layers can always be added later by re-running install.sh."
    PROFILE="full"
    LAYERS=""
    [[ -z "$THEME" ]] && THEME="tokyonight"
    # Return here, not just fall through -- LAYERS="" is this branch's real
    # answer (no optional layers), and the -z checks below can't tell that
    # apart from "not resolved yet," which would otherwise re-trigger
    # prompt_layers right after promising a zero-prompt path.
    return 0
  fi

  [[ -z "$PROFILE" ]] && PROFILE=$(prompt_profile)
  [[ -z "$LAYERS" ]] && LAYERS=$(prompt_layers)
  [[ -z "$THEME" ]] && THEME=$(prompt_theme)
}

write_aphotic_toml() {
  local path="$1" profile="$2" layers="$3" theme="$4" nvidia="$5" aur_helper="$6" installed_at="$7" amd="${8:-false}"

  local layers_toml="[]"
  if [[ -n "$layers" ]]; then
    layers_toml="[$(echo "$layers" | sed -E 's/([^,]+)/"\1"/g; s/,/, /g')]"
  fi

  cat > "$path" <<EOF
[install]
profile = "$profile"
layers = $layers_toml
installed_at = "$installed_at"

[theme]
name = "$theme"

[system]
nvidia = $nvidia
amd = $amd
aur_helper = "$aur_helper"
EOF
}
