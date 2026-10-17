#!/usr/bin/env bash
# shellcheck disable=SC2034  # globals shared across the sourced tui modules
# lib/install/tui/data.sh -- everything the TUI knows about this machine
# and this repo, read without side effects.
#
# Nothing here runs a command that changes state: no sudo, no package
# manager, no git, no writes. That is what lets the Welcome and Review
# screens show real facts before the Run screen exists.

# Field reader for the [meta] table of a profiles/*.toml.
tui_toml_meta() {
  local file="$1" key="$2"
  [[ -r "$file" ]] || return 0
  awk -v key="$key" '
    /^\[/ { inmeta = ($0 == "[meta]") }
    inmeta && $0 ~ "^" key "[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/, "")
      gsub(/^"|"[[:space:]]*$/, "")
      print
      exit
    }
  ' "$file"
}

tui_toml_theme_field() {
  local file="$1" key="$2"
  [[ -r "$file" ]] || return 0
  awk -v key="$key" '
    /^\[theme\]/ { intheme = 1; next }
    /^\[/ { intheme = 0 }
    intheme && $0 ~ "^" key "[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/, "")
      gsub(/^"|"[[:space:]]*$/, "")
      print
      exit
    }
  ' "$file"
}

tui_toml_theme_anchor() {
  local file="$1"
  [[ -r "$file" ]] || return 0
  awk '
    /^\[palette\]/ { inpal = 1; next }
    /^\[/ { inpal = 0 }
    inpal && /^anchor[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "")
      gsub(/^"|"[[:space:]]*$/, "")
      print
      exit
    }
  ' "$file"
}

tui_json_string() {
  local file="$1" key="$2"
  [[ -r "$file" ]] || return 0
  sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n1
}

tui_distro_name() {
  local pretty="" id=""
  if [[ -r /etc/os-release ]]; then
    pretty="$(sed -n 's/^PRETTY_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release | head -n1)"
    id="$(sed -n 's/^ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release | head -n1)"
  fi
  [[ -n "$pretty" ]] && { printf '%s' "$pretty"; return 0; }
  [[ -n "$id" ]] && { printf '%s' "$id"; return 0; }
  printf 'unknown'
}

# Vendors of the display controllers, same read-only lspci pass the
# installer's own failure report uses.
tui_gpu_vendors() {
  command -v lspci >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  local vendors
  vendors="$(lspci -Dmm -nn 2>/dev/null | awk -F '"' '
    $2 ~ /\[(0300|0302|0301)\]$/ {
      vendor = $4
      sub(/ \[[[:xdigit:]]{4}\]$/, "", vendor)
      if (!seen[vendor]++) {
        if (count++) printf ", "
        printf "%s", vendor
      }
    }
    END { if (!count) printf "unknown"; printf "\n" }
  ')"
  printf '%s' "${vendors:-unknown}"
}

tui_has_nvidia() { [[ "$(tui_gpu_vendors)" == *NVIDIA* ]]; }
tui_has_amd() { [[ "$(tui_gpu_vendors)" == *AMD* ]] || [[ "$(tui_gpu_vendors)" == *Advanced* ]]; }

tui_current_channel() {
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/aphotic"
  local f="$state_dir/channel"
  if [[ -r "$f" ]]; then
    local c
    c="$(head -n1 "$f" 2>/dev/null)"
    [[ -n "$c" ]] && { printf '%s' "$c"; return 0; }
  fi
  printf 'stable'
}

tui_existing_install() {
  [[ -f "$TUI_ROOT/aphotic.toml" ]] && return 0
  [[ -x "$HOME/.local/bin/aphotic" ]] && return 0
  return 1
}

tui_backup_root() { printf '%s' "${APHOTIC_BACKUP_ROOT:-$HOME/.config-backup}"; }

tui_backup_count() {
  local root count=0
  root="$(tui_backup_root)"
  [[ -d "$root" ]] || { printf '0'; return 0; }
  count="$(find "$root" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
  printf '%s' "${count:-0}"
}

tui_backup_latest() {
  local root
  root="$(tui_backup_root)"
  [[ -d "$root" ]] || return 0
  find "$root" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort | tail -n1
}

# Fills TUI_PROFILE_NAMES / TUI_PROFILE_DESC. Order is filesystem order,
# which is full then minimal.
tui_load_profiles() {
  TUI_PROFILE_NAMES=() TUI_PROFILE_DESC=()
  local f name desc
  for f in "$TUI_ROOT"/profiles/base/*.toml; do
    [[ -r "$f" ]] || continue
    name="$(basename "$f" .toml)"
    desc="$(tui_toml_meta "$f" description)"
    TUI_PROFILE_NAMES+=("$name")
    TUI_PROFILE_DESC+=("${desc:-$name}")
  done
}

# Fills TUI_LAYER_NAMES / TUI_LAYER_DESC / TUI_LAYER_BLACKARCH /
# TUI_LAYER_MULTILIB. The list is the repo's own profiles/layers, never a
# hardcoded copy.
tui_load_layers() {
  TUI_LAYER_NAMES=() TUI_LAYER_DESC=() TUI_LAYER_BLACKARCH=() TUI_LAYER_MULTILIB=()
  local f name desc ba ml
  for f in "$TUI_ROOT"/profiles/layers/*.toml; do
    [[ -r "$f" ]] || continue
    name="$(basename "$f" .toml)"
    desc="$(tui_toml_meta "$f" description)"
    ba="$(sed -n 's/^requires_blackarch[[:space:]]*=[[:space:]]*//p' "$f" | head -n1)"
    ml="$(sed -n 's/^requires_multilib[[:space:]]*=[[:space:]]*//p' "$f" | head -n1)"
    TUI_LAYER_NAMES+=("$name")
    TUI_LAYER_DESC+=("${desc:-$name}")
    TUI_LAYER_BLACKARCH+=("$ba")
    TUI_LAYER_MULTILIB+=("$ml")
  done
}

# Fills the theme arrays. Colours come from the theme's own anchor
# colorscheme file (Configs/wallust/colorschemes/<anchor>.json); a theme
# without an anchor keeps empty swatch fields and the caller falls back to
# the name alone.
tui_load_themes() {
  TUI_THEME_NAMES=() TUI_THEME_DESC=() TUI_THEME_BG=() TUI_THEME_FG=()
  TUI_THEME_A=() TUI_THEME_B=() TUI_THEME_HAVE=()
  local d name desc anchor cs bg fg ca cb count=0
  for d in "$TUI_ROOT"/Configs/awww/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    desc="$(tui_toml_theme_field "${d}theme.toml" description)"
    anchor="$(tui_toml_theme_anchor "${d}theme.toml")"
    bg="" fg="" ca="" cb=""
    if [[ -n "$anchor" ]]; then
      cs="$TUI_ROOT/Configs/wallust/colorschemes/$anchor.json"
      if [[ -r "$cs" ]]; then
        bg="$(tui_json_string "$cs" background)"
        fg="$(tui_json_string "$cs" foreground)"
        ca="$(tui_json_string "$cs" color4)"
        cb="$(tui_json_string "$cs" color2)"
      fi
    fi
    TUI_THEME_NAMES+=("$name")
    TUI_THEME_DESC+=("${desc:-$name}")
    TUI_THEME_BG+=("$bg")
    TUI_THEME_FG+=("$fg")
    TUI_THEME_A+=("$ca")
    TUI_THEME_B+=("$cb")
    if [[ -n "$bg" && -n "$fg" && -n "$ca" ]]; then
      TUI_THEME_HAVE+=(1)
      count=$((count + 1))
    else
      TUI_THEME_HAVE+=(0)
    fi
  done
  TUI_THEME_SWATCHES=$count
}

# hex -> "r;g;b" truecolour prefix, or empty when not truecolour.
tui_hex_rgb() {
  local hex="$1"
  (( TUI_TRUECOLOR )) || return 0
  [[ "$hex" =~ ^#[0-9A-Fa-f]{6}$ ]] || return 0
  local r g b
  printf -v r '%d' "0x${hex:1:2}"
  printf -v g '%d' "0x${hex:3:2}"
  printf -v b '%d' "0x${hex:5:2}"
  printf '38;2;%d;%d;%d' "$r" "$g" "$b"
}

tui_swatch() {
  local hex="$1" rgb
  [[ -n "$hex" ]] || return 0
  if rgb="$(tui_hex_rgb "$hex")" && [[ -n "$rgb" ]]; then
    printf '\e[48;2;%sm   \e[0m' "${rgb#38;2;}"
  else
    printf '%s    %s' "$TUI_C_MUTED" "$TUI_R"
  fi
}

# Everything the TUI reads at start, all of it side-effect free.
tui_data_init() {
  TUI_VERSION="$(head -n1 "$TUI_ROOT/VERSION" 2>/dev/null || true)"
  TUI_DISTRO="$(tui_distro_name)"
  TUI_GPU="$(tui_gpu_vendors)"
  TUI_NVIDIA=0; tui_has_nvidia && TUI_NVIDIA=1
  TUI_AMD=0; tui_has_amd && TUI_AMD=1
  TUI_CHANNEL_NOW="$(tui_current_channel)"
  TUI_HAS_INSTALL=0; tui_existing_install && TUI_HAS_INSTALL=1
  TUI_BACKUPS="$(tui_backup_count)"
  TUI_BACKUP_LATEST="$(tui_backup_latest)"
  tui_load_profiles
  tui_load_layers
  tui_load_themes
}