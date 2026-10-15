#!/usr/bin/env bash
# install-tui.sh -- menu-driven wrapper over install.sh.
#
# UI only: every answer collected here becomes flags passed to
# ./install.sh. No installer logic lives in this file; install.sh stays
# untouched so the flag-driven path CI depends on is byte-identical.
set -euo pipefail

TUI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TUI_INSTALL_SH="${TUI_INSTALL_SH:-$TUI_ROOT/install.sh}"
TUI_LOG_LINES="${TUI_LOG_LINES:-10}"
TUI_NO_SUDO="${TUI_NO_SUDO:-0}"

# Same one-line tags install.sh uses (wizard.sh echoes $CWR itself).
CNT="[\e[1;36mNOTE\e[0m]"
CER="[\e[1;31mERROR\e[0m]"
CWR="[\e[1;35mWARNING\e[0m]"

source "$TUI_ROOT/lib/install/ui.sh"
source "$TUI_ROOT/lib/install/wizard.sh"

# TUI_STATE: the whole session in one place (choice, profile, layers,
# theme, dry-run flag, the argv built for install.sh). Anything that
# needs the install's domain state reads it from install.sh itself.
TUI_CHOICE=""
TUI_PROFILE=""
TUI_LAYERS=""
TUI_THEME=""
TUI_FORCE_DRYRUN=0
TUI_ARGV=()
TUI_TOTAL_STAGES=""
TUI_STAGE_COLORS=()
TUI_RUNNING=0
TUI_CHILD=0
TUI_SUDO_KEEPALIVE=0
TUI_FIFO=""

# Read stage constants out of install.sh without sourcing it: sourcing
# would execute main (channel-resolve fetch, python bootstrap, the full
# install). grep keeps the wrapper side-effect free.
tui_cleanup() {
  [[ "$TUI_SUDO_KEEPALIVE" != "0" ]] && kill "$TUI_SUDO_KEEPALIVE" 2>/dev/null
  [[ -n "$TUI_FIFO" ]] && rm -f "$TUI_FIFO" 2>/dev/null
  true
}

# Ctrl+C at a menu quits cleanly. Mid-install it asks first (reading
# from /dev/tty, never stdin, so the answer cannot be stolen by the
# installer child sharing stdin); without a terminal it stops at once.
tui_on_int() {
  if [[ "$TUI_RUNNING" != "1" ]]; then
    echo ""
    echo "Quit."
    exit 0
  fi
  local answer="n"
  if [[ -t 0 ]]; then
    echo ""
    read -rp "Abort the install? [y/N] " answer </dev/tty 2>/dev/null || answer="n"
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
      echo "Continuing."
      return 0
    fi
  fi
  echo -e "$CWR - Aborted. Nothing further will be installed."
  [[ "$TUI_CHILD" != "0" ]] && kill "$TUI_CHILD" 2>/dev/null
  exit 130
}

trap tui_cleanup EXIT
trap tui_on_int INT

tui_load_stages() {
  TUI_TOTAL_STAGES="$(sed -n 's/^TOTAL_STAGES=//p' "$TUI_ROOT/install.sh" | head -n1)"
  local line
  line="$(sed -n 's/^STAGE_COLORS=//p' "$TUI_ROOT/install.sh" | head -n1)"
  line="${line#\(}"
  line="${line%\)}"
  read -ra TUI_STAGE_COLORS <<< "$line"
}

tui_stage_color() {
  local n="${1:-1}" count="${#TUI_STAGE_COLORS[@]}"
  ((count > 0)) || { echo "36"; return 0; }
  echo "${TUI_STAGE_COLORS[$(((n - 1) % count))]}"
}

# Banner ASCII duplicates install.sh:print_banner (canonical there) so
# the wrapper shows the same splash without sourcing the installer.
tui_banner() {
  cat <<'EOF'
  █████╗ ██████╗ ██╗  ██╗ ██████╗ ████████╗██╗ ██████╗
 ██╔══██╗██╔══██╗██║  ██║██╔═══██╗╚══██╔══╝██║██╔════╝
 ███████║██████╔╝███████║██║   ██║   ██║   ██║██║
 ██╔══██║██╔═══╝ ██╔══██║██║   ██║   ██║   ██║██║
 ██║  ██║██║     ██║  ██║╚██████╔╝   ██║   ██║╚██████╗
 ╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚═╝ ╚═════╝
           ██╗  ██╗██╗   ██╗██████╗ ██████╗
           ██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗
           ███████║ ╚████╔╝ ██████╔╝██████╔╝
           ██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗
           ██║  ██║   ██║   ██║     ██║  ██║
           ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝
EOF
  echo "APHOTIC installer -- menu-driven setup (${TUI_TOTAL_STAGES} stages)"
}

tui_menu_line() {
  local idx="$1" text="$2" sel="$3"
  if [[ "$idx" == "$sel" ]]; then
    echo "  > $idx) $text"
  else
    echo "    $idx) $text"
  fi
}

# Number+Enter always works (pipes, serial, tests). On a real terminal
# arrow keys move and Enter picks; q or Esc quits anywhere.
tui_menu() {
  local items=("Install Aphotic" "Dry-run preview" "Guided answers" "Exit")
  local sel=1 key rest line
  while true; do
    echo ""
    echo "What now? (number + Enter; arrows + Enter on a terminal, q quits)"
    local i
    for i in 1 2 3 4; do
      tui_menu_line "$i" "${items[$((i - 1))]}" "$sel"
    done
    if [[ -t 0 ]]; then
      IFS= read -rsn1 key || { TUI_CHOICE="4"; return 0; }
      case "$key" in
        $'\e') IFS= read -t 0.2 -rsn2 rest || rest=""; key+="$rest" ;;
        "") TUI_CHOICE="$sel"; return 0 ;;
        [1-4]) TUI_CHOICE="$key"; return 0 ;;
        q|Q) TUI_CHOICE="4"; return 0 ;;
      esac
      case "$key" in
        $'\e') TUI_CHOICE="4"; return 0 ;;
        $'\e[A') ((sel > 1)) && ((sel--)) || true ;;
        $'\e[B') ((sel < 4)) && ((sel++)) || true ;;
      esac
    else
      IFS= read -r line || { TUI_CHOICE="4"; return 0; }
      case "$line" in
        1|2|3|4) TUI_CHOICE="$line"; return 0 ;;
        q|Q|quit|exit) TUI_CHOICE="4"; return 0 ;;
        "") TUI_CHOICE="4"; return 0 ;;
        *) echo "Pick 1-4 (or q to quit)." ;;
      esac
    fi
  done
}

tui_collect_answers() {
  TUI_PROFILE="$(prompt_profile)"
  TUI_LAYERS="$(prompt_layers 2)"
  TUI_THEME="$(prompt_theme)"
}

tui_build_argv() {
  TUI_ARGV=()
  [[ -n "$TUI_PROFILE" ]] && TUI_ARGV+=(--profile "$TUI_PROFILE")
  [[ -n "$TUI_LAYERS" ]] && TUI_ARGV+=(--with "$TUI_LAYERS")
  [[ -n "$TUI_THEME" ]] && TUI_ARGV+=(--theme "$TUI_THEME")
  if [[ "$TUI_CHOICE" == "2" || "$TUI_FORCE_DRYRUN" == "1" ]]; then
    TUI_ARGV+=(--dry-run)
  fi
}

# sudo reads the password from the terminal itself, before any logging
# starts. The wrapper never prompts for, echoes, or logs a password.
tui_sudo_upfront() {
  [[ "$TUI_NO_SUDO" == "1" ]] && return 0
  [[ -t 0 ]] || return 0
  command -v sudo >/dev/null 2>&1 || return 0
  echo -e "$CNT - Checking sudo access (ask sudo, not this wrapper)."
  sudo -v || { echo -e "$CER - sudo access is required to install."; return 1; }
  (
    while kill -0 "$$" 2>/dev/null; do
      sudo -n true 2>/dev/null || exit 0
      sleep 50
    done
  ) &
  TUI_SUDO_KEEPALIVE=$!
}

tui_log_pane() {
  echo "--- install.log (last $TUI_LOG_LINES lines) ---"
  if [[ -f install.log ]]; then
    tail -n "$TUI_LOG_LINES" install.log
  else
    echo "(no install.log yet)"
  fi
}

tui_run_installer() {
  local status=0
  if [[ -t 1 ]]; then
    echo -e "\e[1;$(tui_stage_color 1)m── install.sh ${TUI_ARGV[*]:-} ──\e[0m"
  else
    echo -e "$CNT - Running: install.sh ${TUI_ARGV[*]:-}"
  fi
  TUI_FIFO="$(mktemp -u)"
  mkfifo "$TUI_FIFO"
  tee -a install.log <"$TUI_FIFO" &
  local tee_pid=$!
  "$TUI_INSTALL_SH" "${TUI_ARGV[@]}" >"$TUI_FIFO" 2>&1 &
  TUI_CHILD=$!
  TUI_RUNNING=1
  while kill -0 "$TUI_CHILD" 2>/dev/null; do
    wait "$TUI_CHILD" && status=0 || status=$?
  done
  TUI_RUNNING=0
  TUI_CHILD=0
  wait "$tee_pid" 2>/dev/null || true
  tui_log_pane
  return "$status"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) TUI_FORCE_DRYRUN=1; shift ;;
      -h|--help) echo "Usage: ./install-tui.sh [--dry-run]"; exit 0 ;;
      *) echo -e "$CER - Unknown option: $1"; exit 1 ;;
    esac
  done
  tui_load_stages
  tui_banner
  tui_menu
  case "$TUI_CHOICE" in
    4) exit 0 ;;
    3) tui_build_argv ;;
    1|2)
      tui_collect_answers
      tui_build_argv
      ;;
  esac
  tui_sudo_upfront
  tui_run_installer
}

main "$@"
