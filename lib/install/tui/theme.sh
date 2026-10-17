#!/usr/bin/env bash
# shellcheck disable=SC2034  # globals shared across the sourced tui modules
# lib/install/tui/theme.sh -- terminal control and the Aphotic render language.
#
# The look follows the Signal design language: a near-black resting state,
# one thin hairline that lights where something is live, and accents only
# on state. Truecolour when the terminal offers it, the 16-colour palette
# when it does not, plain text when colour is off.

# Colour depth: "true", "256", "16" or "none". NO_COLOR and a dumb terminal
# both drop to none, which is what makes the plain numbered fallback plain.
tui_colour_level() {
  case "${NO_COLOR:-}" in "") ;; *) echo none; return 0 ;; esac
  case "${TERM:-}" in ""|dumb) echo none; return 0 ;; esac
  case "${COLORTERM:-}" in truecolor|24bit) echo true; return 0 ;; esac
  case "${TERM:-}" in *-direct|*-truecolor|*direct*) echo true; return 0 ;; esac
  case "${TERM:-}" in *-256color|*-256|xterm-kitty|alacritty|wezterm|foot|tmux*) echo 256 ;; *) echo 16 ;; esac
}

tui_init_colour() {
  TUI_LEVEL="$(tui_colour_level)"
  TUI_R="" TUI_BOLD="" TUI_DIM="" TUI_C_INK="" TUI_C_MUTED="" TUI_C_ACCENT=""
  TUI_C_LIVE="" TUI_C_OK="" TUI_C_WARN="" TUI_C_ERR="" TUI_C_HAIR=""
  case "$TUI_LEVEL" in
    true)
      TUI_R=$'\e[0m'; TUI_BOLD=$'\e[1m'; TUI_DIM=$'\e[2m'
      TUI_C_INK=$'\e[38;2;230;230;234m'
      TUI_C_MUTED=$'\e[38;2;110;112;128m'
      TUI_C_ACCENT=$'\e[38;2;138;160;216m'
      TUI_C_LIVE=$'\e[38;2;157;206;214m'
      TUI_C_OK=$'\e[38;2;111;191;139m'
      TUI_C_WARN=$'\e[38;2;216;166;92m'
      TUI_C_ERR=$'\e[38;2;217;122;122m'
      TUI_C_HAIR=$'\e[38;2;48;50;62m'
      ;;
    256)
      TUI_R=$'\e[0m'; TUI_BOLD=$'\e[1m'; TUI_DIM=$'\e[2m'
      TUI_C_INK=$'\e[38;5;253m'
      TUI_C_MUTED=$'\e[38;5;243m'
      TUI_C_ACCENT=$'\e[38;5;110m'
      TUI_C_LIVE=$'\e[38;5;116m'
      TUI_C_OK=$'\e[38;5;114m'
      TUI_C_WARN=$'\e[38;5;179m'
      TUI_C_ERR=$'\e[38;5;174m'
      TUI_C_HAIR=$'\e[38;5;237m'
      ;;
    16)
      TUI_R=$'\e[0m'; TUI_BOLD=$'\e[1m'; TUI_DIM=$'\e[2m'
      TUI_C_INK=$'\e[37m'
      TUI_C_MUTED=$'\e[90m'
      TUI_C_ACCENT=$'\e[36m'
      TUI_C_LIVE=$'\e[1;36m'
      TUI_C_OK=$'\e[32m'
      TUI_C_WARN=$'\e[33m'
      TUI_C_ERR=$'\e[31m'
      TUI_C_HAIR=$'\e[90m'
      ;;
    *) TUI_LEVEL="none" ;;
  esac
  if [[ "$TUI_LEVEL" == "none" ]]; then TUI_COLOR_ON=0; else TUI_COLOR_ON=1; fi
  if [[ "$TUI_LEVEL" == "true" ]]; then TUI_TRUECOLOR=1; else TUI_TRUECOLOR=0; fi
  TUI_CH_H="${TUI_CHAR_H:--}"
}

# Measured once so a later resize can be noticed against the old value.
tui_measure() {
  local cols lines
  cols="$(tput cols 2>/dev/null)" || cols=""
  lines="$(tput lines 2>/dev/null)" || lines=""
  [[ "$cols" =~ ^[0-9]+$ ]] || cols="${COLUMNS:-80}"
  [[ "$lines" =~ ^[0-9]+$ ]] || lines="${LINES:-24}"
  TUI_COLS="$cols"
  TUI_LINES="$lines"
}

tui_size_ok() {
  (( TUI_COLS >= 80 && TUI_LINES >= 24 ))
}

tui_too_small() {
  printf '%s\n' "Aphotic needs a terminal of at least 80x24." \
    "This one is ${TUI_COLS}x${TUI_LINES}." \
    "Resize it and run the installer again." >&2
}

tui_clear() {
  (( TUI_INTERACTIVE )) || return 0
  printf '\e[H\e[2J'
}

tui_enter_alt() {
  (( TUI_INTERACTIVE )) || return 0
  printf '\e[?1049h'
  TUI_ALT=1
}

tui_leave_alt() {
  [[ "$TUI_ALT" == "1" ]] || return 0
  printf '\e[?1049l'
  TUI_ALT=0
}

tui_cursor_hide() { (( TUI_INTERACTIVE )) && printf '\e[?25l' || true; }
tui_cursor_show() { printf '\e[?25h'; }

# Restore every mode the TUI turned on, on any exit path.
tui_restore() {
  (( TUI_INTERACTIVE )) && tui_cursor_show
  tui_leave_alt
  if [[ -n "${TUI_STTY_SAVED:-}" ]]; then
    stty "$TUI_STTY_SAVED" 2>/dev/null || true
    TUI_STTY_SAVED=""
  fi
}

# A hairline across the width. `lit` is how many columns of it are live, so
# a screen can show progress by lighting the line from the left.
tui_rule() {
  local lit="${1:-0}" i line=""
  (( lit > TUI_COLS )) && lit="$TUI_COLS"
  (( lit < 0 )) && lit=0
  for (( i = 1; i <= TUI_COLS; i++ )); do line+="$TUI_CH_H"; done
  if (( TUI_COLOR_ON )); then
    printf '%s%s%s%s%s\n' "$TUI_C_HAIR" "${line:0:lit}" "$TUI_C_LIVE" "${line:lit}" "$TUI_R"
  else
    printf '%s\n' "$line"
  fi
}

# The wordmark. A hairline opens around the name, the name sits in the gap
# lit, and a caption carries the product name and version underneath.
tui_wordmark() {
  local name="A P H O T I C" inner left right ver
  ver="${TUI_VERSION:-}"
  inner="${#name}"
  (( TUI_COLS > inner + 4 )) || { printf '%s\n' "$name"; return 0; }
  left=$(( (TUI_COLS - inner) / 2 - 2 ))
  right=$(( TUI_COLS - inner - 4 - left ))
  (( left < 0 )) && left=0
  (( right < 0 )) && right=0
  printf '%*s' "$left" ''
  printf '%s%s%s' "$TUI_C_HAIR" "$(tui_rep "$TUI_CH_H" 2)" "$TUI_C_LIVE"
  printf '%s%s%s' "$TUI_C_ACCENT" "$TUI_BOLD" " $name "
  printf '%s%s' "$TUI_C_LIVE" "$TUI_R"
  printf '%s%s%s\n' "$TUI_C_HAIR" "$(tui_rep "$TUI_CH_H" 2)" "$TUI_R"
  printf '%s\n' "$(tui_center "Aphotic  installer${ver:+  v$ver}" )"
}

tui_rep() {
  local ch="$1" n="$2" out="" i
  for (( i = 0; i < n; i++ )); do out+="$ch"; done
  printf '%s' "$out"
}

tui_center() {
  local text="$1" pad
  (( pad = (TUI_COLS - ${#text}) / 2 ))
  (( pad < 0 )) && pad=0
  printf '%*s%s' "$pad" '' "$text"
}

# Screen title with a running step counter, drawn over the hairline.
tui_title() {
  local step="$1" total="$2" name="$3"
  printf '\n%s%s[%s/%s]%s %s%s%s\n' "$TUI_C_ACCENT" "$TUI_BOLD" "$step" "$total" "$TUI_R" "$TUI_BOLD" "$name" "$TUI_R"
}

tui_note() {
  local role="$1" text="$2"
  case "$role" in
    ok) printf '  %s%s %s%s\n' "$TUI_C_OK" "$TUI_OK_GLYPH" "$text" "$TUI_R" ;;
    warn) printf '  %s%s %s%s\n' "$TUI_C_WARN" "$TUI_WARN_GLYPH" "$text" "$TUI_R" ;;
    err) printf '  %s%s %s%s\n' "$TUI_C_ERR" "$TUI_ERR_GLYPH" "$text" "$TUI_R" ;;
    muted) printf '  %s%s%s\n' "$TUI_C_MUTED" "$text" "$TUI_R" ;;
    *) printf '  %s\n' "$text" ;;
  esac
}

tui_hint() {
  printf '%s%s%s\n' "$TUI_C_MUTED" "$1" "$TUI_R"
}

tui_glyph_init() {
  if (( TUI_COLOR_ON )); then
    TUI_OK_GLYPH="+" TUI_WARN_GLYPH="!" TUI_ERR_GLYPH="x"
    TUI_ON_GLYPH="[*]" TUI_OFF_GLYPH="[ ]"
    TUI_ACTIVE_GLYPH=">" TUI_DOT="·"
  else
    TUI_OK_GLYPH="+" TUI_WARN_GLYPH="!" TUI_ERR_GLYPH="x"
    TUI_ON_GLYPH="[x]" TUI_OFF_GLYPH="[ ]"
    TUI_ACTIVE_GLYPH=">" TUI_DOT="."
  fi
}