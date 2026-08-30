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

prompt_profile() {
  local answer
  read -rp "Profile? [minimal/full] (full): " answer
  answer="${answer:-full}"
  if [[ "$answer" != "minimal" && "$answer" != "full" ]]; then
    echo "full"
  else
    echo "$answer"
  fi
}

prompt_layers() {
  local layers=()
  local answer

  # Presets are a shortcut over the same layer list the questions below
  # build -- not a second mechanism. "Cherry-pick" is just answering them.
  echo "Layer presets:" >&2
  echo "  1) Everything       -- gaming, dev, ai, and the default exploit bundle" >&2
  echo "  2) Daily driver     -- none of the above; a clean Hyprland desktop" >&2
  echo "  3) Cherry-pick      -- choose each layer yourself" >&2
  read -rp "Preset? [1/2/3, default 3]: " answer
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

  read -rp "Enable gaming layer? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] && layers+=("gaming")

  read -rp "Enable dev layer? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] && layers+=("dev")

  # Say what this actually does before asking: it is the only layer that
  # writes into a config file outside this repo (~/.claude/settings.json).
  read -rp "Enable ai layer? Adds the agent graph, AI chat and live Claude Code session tracking -- wires hooks into ~/.claude/settings.json and enables a usage-tracking timer [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] && layers+=("ai")

  read -rp "Enable exploit/offensive-security tooling? Adds the BlackArch repo for most sublayers -- less stable than Arch's official repos, see docs/exploit-layer.md [y/N]: " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    read -rp "  Use the default bundle (recon + web + network)? [Y/n]: " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
      layers+=("exploit")
    else
      read -rp "  Enable exploit-recon (nmap, amass, subfinder, theHarvester, recon-ng)? [y/N]: " answer
      [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-recon")

      read -rp "  Enable exploit-web (Burp Suite CE, sqlmap, ffuf, gobuster, nikto, ZAP)? [y/N]: " answer
      [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-web")

      read -rp "  Enable exploit-network (Wireshark, aircrack-ng, bettercap, tcpdump)? [y/N]: " answer
      [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-network")
    fi

    read -rp "  Enable exploit-passwords (John the Ripper, hashcat, Hydra)? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      layers+=("exploit-passwords")
      read -rp "    Also fetch the rockyou wordlist? ~130MB decompressed, from the OWASP SecLists project -- always separate, never bundled automatically [y/N]: " answer
      [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-wordlists")
    fi

    read -rp "  Enable exploit-reversing (Ghidra, radare2, Cutter, gdb+pwndbg, binwalk)? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-reversing")

    read -rp "  Enable exploit-forensics (Autopsy, Sleuth Kit, Volatility 3)? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-forensics")

    read -rp "  Enable exploit-reporting (engagement report scaffolding, aphotic report CLI)? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-reporting")
  fi

  local IFS=","
  echo "${layers[*]}"
}

prompt_theme() {
  local answer
  read -rp "Theme? (default): " answer
  echo "${answer:-default}"
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

# Resolves PROFILE/LAYERS/THEME for a fresh (non---config-only) install.
#
# Default, with none of --profile/--with/--opt-in passed, is the
# zero-prompt "daily driver" path -- full profile, no optional layers. A
# brand-new Arch/Hyprland user shouldn't have to know what a "layer" or
# "profile" is before they can finish installing; --opt-in restores the
# full interactive cherry-pick wizard below for anyone who wants it, and
# any of --profile/--with/--theme passed directly always wins over both.
#
# This is a deliberate judgment call, not a mechanical default: real
# layer packages still only install via this terminal flow today (no
# other mechanism exists yet), so the wizard itself isn't going away, just
# no longer imposed on every fresh install by default. See the PR
# description for the fuller reasoning and why a post-first-launch picker
# isn't built here instead.
resolve_config() {
  # Reuses detect.sh's already-computed findings (stage 1) rather than
  # re-querying aphotic.toml here -- the whole point of a consolidated
  # detection pass is that later stages consume it instead of repeating it.
  if [[ "$DETECTED_APHOTIC_INSTALL" == "1" && -z "$PROFILE" && -z "$LAYERS" ]]; then
    echo -e "$CNT - Existing config found (profile=$DETECTED_APHOTIC_PROFILE, layers=${DETECTED_APHOTIC_LAYERS:-none})."
    if [[ -t 0 ]]; then
      if confirm "Reinstall same config?" y; then
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
    echo -e "$CNT - Run with --opt-in for the interactive layer picker, or --with gaming,dev,ai,exploit to pick layers directly. Layers can always be added later by re-running install.sh."
    PROFILE="full"
    LAYERS=""
    [[ -z "$THEME" ]] && THEME="default"
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
  local path="$1" profile="$2" layers="$3" theme="$4" nvidia="$5" aur_helper="$6" installed_at="$7"

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
aur_helper = "$aur_helper"
EOF
}
