#!/usr/bin/env bash
# install-tui.sh -- a keyboard-driven installer over install.sh.
#
# UI only: every answer collected here becomes flags on a single
# ./install.sh command line. install.sh and its lib/install stage files stay
# untouched, so the flag-driven path CI depends on is byte-identical. The
# installer runs once, from the Run screen; every screen before it reads
# only.
set -euo pipefail

TUI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TUI_INSTALL_SH="${TUI_INSTALL_SH:-$TUI_ROOT/install.sh}"
TUI_LOG_LINES="${TUI_LOG_LINES:-10}"
TUI_NO_SUDO="${TUI_NO_SUDO:-0}"

TUI_INTERACTIVE=0
TUI_ALT=0
TUI_RESIZED=0
TUI_STTY_SAVED=""
TUI_SUDO_KEEPALIVE=0
TUI_CHILD=0
TUI_RUNNING=0
TUI_FIFO=""
TUI_FORCE_DRYRUN=0
TUI_RING=()
TUI_FLOW=()
TUI_ARGV=()

# UTF-8 terminals get the U+2500 hairline; others get a hyphen.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) TUI_CHAR_H="─"; TUI_ELLIPSIS="…" ;;
  *) TUI_CHAR_H="-"; TUI_ELLIPSIS="..." ;;
esac

# shellcheck source=lib/install/tui/theme.sh
source "$TUI_ROOT/lib/install/tui/theme.sh"
# shellcheck source=lib/install/tui/data.sh
source "$TUI_ROOT/lib/install/tui/data.sh"
# shellcheck source=lib/install/tui/menu.sh
source "$TUI_ROOT/lib/install/tui/menu.sh"
# shellcheck source=lib/install/tui/screens.sh
source "$TUI_ROOT/lib/install/tui/screens.sh"
# shellcheck source=lib/install/tui/run.sh
source "$TUI_ROOT/lib/install/tui/run.sh"

tui_cleanup() {
  tui_restore
  [[ "$TUI_SUDO_KEEPALIVE" != "0" ]] && kill "$TUI_SUDO_KEEPALIVE" 2>/dev/null
  [[ -n "$TUI_FIFO" ]] && rm -f "$TUI_FIFO" 2>/dev/null
  true
}

# Ctrl+C at a menu quits cleanly. Mid-install it asks first, reading from
# /dev/tty so the answer cannot be stolen by the installer child.
tui_on_int() {
  if [[ "$TUI_RUNNING" != "1" ]]; then
    tui_restore
    printf '\nQuit. Nothing was changed.\n'
    exit 0
  fi
  tui_restore
  local answer="n"
  if [[ -t 0 ]]; then
    printf '\nAbort the install? [y/N] '
    IFS= read -r answer </dev/tty 2>/dev/null || answer="n"
  fi
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    tui_cursor_hide
    return 0
  fi
  printf '\nAborted. Nothing further will be installed.\n'
  [[ "$TUI_CHILD" != "0" ]] && kill "$TUI_CHILD" 2>/dev/null
  exit 130
}

tui_on_winch() { TUI_RESIZED=1; }

tui_build_argv() {
  TUI_ARGV=()
  if [[ "$TUI_MODE" == "config" ]]; then
    TUI_ARGV+=(--config-only)
    TUI_ARGV+=(--channel "$TUI_CHANNEL")
    return 0
  fi
  TUI_ARGV+=(--channel "$TUI_CHANNEL")
  TUI_ARGV+=(--profile "$TUI_PROFILE")
  if [[ -n "$TUI_LAYERS_CSV" ]]; then TUI_ARGV+=(--with "$TUI_LAYERS_CSV"); fi
  if [[ -n "$TUI_THEME" ]]; then TUI_ARGV+=(--theme "$TUI_THEME"); fi
  case "$TUI_ASSISTANT" in
    on) TUI_ARGV+=(--with-assistant) ;;
    off) TUI_ARGV+=(--no-assistant) ;;
  esac
  (( TUI_KEEP_SDDM )) && TUI_ARGV+=(--keep-sddm) || true
  if [[ -n "$TUI_NVIDIA_ACTION" ]]; then TUI_ARGV+=(--nvidia-driver "$TUI_NVIDIA_ACTION"); fi
  case "$TUI_CONFLICTS" in
    strip) TUI_ARGV+=(--strip-conflicts) ;;
    keep) TUI_ARGV+=(--keep-conflicts) ;;
  esac
  (( TUI_NO_BACKUP )) && TUI_ARGV+=(--no-backup) || true
  if [[ "$TUI_KEEP_BACKUPS" != "5" ]]; then TUI_ARGV+=(--keep-backups "$TUI_KEEP_BACKUPS"); fi
  (( TUI_ACCEPT_EXPLOIT )) && TUI_ARGV+=(--accept-exploit-disclaimer) || true
  if [[ "$TUI_MODE" == "dry" || "$TUI_FORCE_DRYRUN" == "1" ]]; then TUI_ARGV+=(--dry-run); fi
  return 0
}

tui_build_flow() {
  TUI_FLOW=("welcome" "channel")
  if [[ "$TUI_MODE" != "config" ]]; then
    TUI_FLOW+=("profile" "layers" "theme" "assistant" "display")
    if (( TUI_NVIDIA )); then TUI_FLOW+=("nvidia"); fi
    TUI_FLOW+=("conflicts" "backup")
    if (( TUI_EXPLOIT_SELECTED )); then TUI_FLOW+=("exploit"); fi
  fi
  TUI_FLOW+=("review")
}

tui_defaults() {
  TUI_MODE="full"
  TUI_CHANNEL="$TUI_CHANNEL_NOW"
  TUI_PROFILE="full"
  TUI_LAYERS_CSV=""
  TUI_THEME="tokyonight"
  TUI_ASSISTANT="off"
  TUI_KEEP_SDDM=0
  TUI_NVIDIA_ACTION="keep"
  TUI_CONFLICTS=""
  TUI_NO_BACKUP=0
  TUI_KEEP_BACKUPS=5
  TUI_ACCEPT_EXPLOIT=0
  TUI_EXPLOIT_SELECTED=0
  local i
  for i in "${!TUI_PROFILE_NAMES[@]}"; do
    [[ "${TUI_PROFILE_NAMES[$i]}" == "full" ]] || continue
  done
  [[ ${#TUI_PROFILE_NAMES[@]} -gt 0 ]] || TUI_PROFILE="minimal"
  for i in "${!TUI_THEME_NAMES[@]}"; do
    [[ "${TUI_THEME_NAMES[$i]}" == "tokyonight" ]] && return 0
  done
  [[ ${#TUI_THEME_NAMES[@]} -gt 0 ]] && TUI_THEME="${TUI_THEME_NAMES[0]}"
  return 0
}

tui_assistant_implies_ai() {
  [[ "$TUI_ASSISTANT" == "on" ]] || return 0
  [[ ",$TUI_LAYERS_CSV," == *",ai,"* ]] && return 0
  if [[ -n "$TUI_LAYERS_CSV" ]]; then TUI_LAYERS_CSV+=",ai"; else TUI_LAYERS_CSV="ai"; fi
}

tui_driver() {
  local index=0 jump_review=0 total step rc st
  while :; do
    tui_build_flow
    total="${#TUI_FLOW[@]}"
    (( index >= total )) && break
    step="${TUI_FLOW[$index]}"
    rc=0
    "tui_step_${step}" || rc=$?
    if [[ "$step" == "review" ]]; then
      case "$rc" in
        0)
          tui_assistant_implies_ai
          tui_build_argv
          if ! tui_sudo_upfront; then
            tui_note err "Cannot install without sudo access."
            return 1
          fi
          st=0
          tui_run_installer || st=$?
          tui_finish "$st" || true
          return "$st"
          ;;
        1) index=$((index - 1)); (( index < 0 )) && index=0 ;;
        2) index="$TUI_REVIEW_TARGET" ;;
        3) return 0 ;;
      esac
      continue
    fi
    case "$rc" in
      3) return 0 ;;
      1) index=$((index - 1)); (( index < 0 )) && index=0 ;;
      *)
        if (( jump_review )); then
          jump_review=0
          tui_build_flow
          index=$(( ${#TUI_FLOW[@]} - 1 ))
        else
          index=$((index + 1))
        fi
        ;;
    esac
  done
  return 0
}

tui_help() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--help] [--version]

  A keyboard-driven interface over ./install.sh. Point it at another copy
  with \$TUI_INSTALL_SH. Answer everything before the Run screen; nothing
  changes on disk until then.

  --dry-run      hand install.sh --dry-run no matter what Welcome says
  --help         this text
  --version      print the Aphotic version and exit
EOF
}

tui_parse_args() {
  TUI_FORCE_DRYRUN=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) TUI_FORCE_DRYRUN=1; shift ;;
      -h|--help) tui_help; exit 0 ;;
      -v|--version) cat "$TUI_ROOT/VERSION" 2>/dev/null || true; exit 0 ;;
      *) printf 'Unknown option: %s\n' "$1" >&2; tui_help >&2; exit 1 ;;
    esac
  done
}

main() {
  tui_parse_args "$@"
  tui_init_colour
  tui_glyph_init
  tui_measure

  if [[ -t 0 && -t 1 && "${TUI_FORCE_PLAIN:-0}" != "1" ]]; then
    TUI_INTERACTIVE=1
  fi
  if (( TUI_INTERACTIVE )); then
    if ! tui_size_ok; then
      tui_too_small
      exit 1
    fi
    TUI_STTY_SAVED="$(stty -g 2>/dev/null || true)"
    tui_enter_alt
    tui_cursor_hide
  fi

  trap tui_cleanup EXIT
  trap tui_on_int INT
  trap tui_on_winch WINCH

  tui_data_init
  tui_defaults
  tui_load_stages
  [[ "$TUI_FORCE_DRYRUN" == "1" && "$TUI_MODE" != "config" ]] && true

  tui_driver
}

main "$@"