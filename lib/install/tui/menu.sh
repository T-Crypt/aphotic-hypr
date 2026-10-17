#!/usr/bin/env bash
# shellcheck disable=SC2034  # globals shared across the sourced tui modules
# lib/install/tui/menu.sh -- keyboard menus.
#
# Two shapes of the same question. On a terminal the list redraws in place,
# arrows or j/k move, space toggles, enter confirms, esc or b backs out. On
# a pipe, a serial console, or a dumb terminal every question is a numbered
# line read from stdin, so tests and scripts drive it the same way.

# Read one key from the terminal into TUI_KEY. Arrows arrive as escape
# sequences; a lone escape is "back".
tui_read_key() {
  local k rest
  IFS= read -rsn1 k || { TUI_KEY="eof"; return 0; }
  case "$k" in
    $'\e')
      IFS= read -rsn2 -t 0.05 rest 2>/dev/null || rest=""
      case "$rest" in
        "[A") TUI_KEY="up" ;;
        "[B") TUI_KEY="down" ;;
        "[C") TUI_KEY="right" ;;
        "[D") TUI_KEY="left" ;;
        "") TUI_KEY="back" ;;
        *) TUI_KEY="unknown" ;;
      esac
      ;;
    "") TUI_KEY="enter" ;;
    " ") TUI_KEY="space" ;;
    q|Q) TUI_KEY="quit" ;;
    b|B) TUI_KEY="back" ;;
    j|J) TUI_KEY="down" ;;
    k|K) TUI_KEY="up" ;;
    [0-9]) TUI_KEY="num:$k" ;;
    *) TUI_KEY="char:$k" ;;
  esac
}

tui_menu_confirm_quit() {
  local answer=""
  printf '\n%sQuit the installer? Nothing has been changed.%s [y/N] ' "$TUI_C_WARN" "$TUI_R"
  IFS= read -r answer </dev/tty 2>/dev/null || answer="n"
  printf '\n'
  [[ "$answer" =~ ^[Yy]$ ]]
}

# Draw the option list. Sets TUI_DRAWN to the number of lines printed so the
# interactive loop can move back up and redraw in place.
tui_pick_draw() {
  local title="$1" sel="$2" i
  printf '\n  %s%s%s\n' "$TUI_BOLD" "$title" "$TUI_R"
  for i in "${!TUI_ITEMS[@]}"; do
    if [[ "${TUI_DISABLED[$i]:-0}" == "1" ]]; then
      printf '  %s%s%d) %s%s\n' "$TUI_C_MUTED" "$TUI_DIM" "$((i + 1))" "${TUI_ITEMS[$i]}" "$TUI_R"
    elif (( i == sel )); then
      printf '  %s%s%s %d) %s%s\n' "$TUI_C_LIVE" "$TUI_BOLD" "$TUI_ACTIVE_GLYPH" "$((i + 1))" "${TUI_ITEMS[$i]}" "$TUI_R"
    else
      printf '    %s%d) %s%s\n' "$TUI_C_INK" "$((i + 1))" "${TUI_ITEMS[$i]}" "$TUI_R"
    fi
    if [[ -n "${TUI_DESC[$i]:-}" ]]; then
      printf '       %s%s%s\n' "$TUI_C_MUTED" "${TUI_DESC[$i]}" "$TUI_R"
    fi
  done
  TUI_DRAWN=$(( ${#TUI_ITEMS[@]} + 2 ))
  local desc_count=0
  for i in "${!TUI_DESC[@]}"; do [[ -n "${TUI_DESC[$i]:-}" ]] && desc_count=$((desc_count + 1)); done
  TUI_DRAWN=$(( TUI_DRAWN + desc_count ))
}

# tui_pick <title> <default-index> <var> [hint]
# Stores the chosen 1-based index in <var>. Returns 0 ok, 1 back, 3 quit.
tui_pick() {
  local title="$1" default="$2" var="$3" hint="${4:-}" i answer
  local count="${#TUI_ITEMS[@]}"
  local sel=$(( default - 1 ))
  (( sel < 0 )) && sel=0
  (( sel >= count )) && sel=$(( count - 1 ))

  if (( ! TUI_INTERACTIVE )); then
    printf '\n  %s\n' "$title"
    for i in "${!TUI_ITEMS[@]}"; do
      printf '    %d) %s' "$((i + 1))" "${TUI_ITEMS[$i]}"
      [[ -n "${TUI_DESC[$i]:-}" ]] && printf ' -- %s' "${TUI_DESC[$i]}"
      [[ "${TUI_DISABLED[$i]:-0}" == "1" ]] && printf ' (unavailable)'
      printf '\n'
    done
    printf '  Choose 1-%d [default %d]: ' "$count" "$((sel + 1))"
    if ! IFS= read -r answer; then return 3; fi
    case "$answer" in
      "") ;;
      q|Q) return 3 ;;
      b|B) return 1 ;;
      *[!0-9]*) printf '  Not a number, using %d.\n' "$((sel + 1))" ;;
      *)
        if (( answer >= 1 && answer <= count )) && [[ "${TUI_DISABLED[$((answer - 1))]:-0}" != "1" ]]; then
          sel=$(( answer - 1 ))
        else
          printf '  Out of range, using %d.\n' "$((sel + 1))"
        fi
        ;;
    esac
    printf -v "$var" '%s' "$((sel + 1))"
    return 0
  fi

  tui_pick_draw "$title" "$sel"
  [[ -n "$hint" ]] && tui_hint "$hint"
  while :; do
    tui_read_key
    if (( TUI_RESIZED )); then
      TUI_RESIZED=0; tui_measure
      tui_clear; tui_wordmark; printf '\n'
      tui_pick_draw "$title" "$sel"
      [[ -n "$hint" ]] && tui_hint "$hint"
      continue
    fi
    case "$TUI_KEY" in
      up) (( sel > 0 )) && sel=$((sel - 1)) || true ;;
      down) (( sel < count - 1 )) && sel=$((sel + 1)) || true ;;
      enter) printf '\n'; printf -v "$var" '%s' "$((sel + 1))"; return 0 ;;
      back) printf '\n'; return 1 ;;
      quit) if tui_menu_confirm_quit; then return 3; else printf '\e[%dA' "$TUI_DRAWN"; tui_pick_draw "$title" "$sel"; [[ -n "$hint" ]] && tui_hint "$hint"; continue; fi ;;
      eof) printf '\n'; return 3 ;;
      num:*)
        local n="${TUI_KEY#num:}"
        if (( n >= 1 && n <= count )) && [[ "${TUI_DISABLED[$((n - 1))]:-0}" != "1" ]]; then
          sel=$(( n - 1 ))
        fi
        ;;
      *) continue ;;
    esac
    printf '\e[%dA' "$TUI_DRAWN"
    tui_pick_draw "$title" "$sel"
    [[ -n "$hint" ]] && tui_hint "$hint"
  done
}

tui_multi_draw() {
  local title="$1" sel="$2" i
  printf '\n  %s%s%s\n' "$TUI_BOLD" "$title" "$TUI_R"
  for i in "${!TUI_ITEMS[@]}"; do
    local mark="${TUI_OFF_GLYPH}"
    [[ "${TUI_SELECTED[$i]:-0}" == "1" ]] && mark="${TUI_ON_GLYPH}"
    if [[ "${TUI_DISABLED[$i]:-0}" == "1" ]]; then
      printf '  %s%s %s %d) %s%s\n' "$TUI_C_MUTED" "$TUI_DIM" "$mark" "$((i + 1))" "${TUI_ITEMS[$i]}" "$TUI_R"
    elif (( i == sel )); then
      printf '  %s%s%s %s %d) %s%s\n' "$TUI_C_LIVE" "$TUI_BOLD" "$TUI_ACTIVE_GLYPH" "$mark" "$((i + 1))" "${TUI_ITEMS[$i]}" "$TUI_R"
    else
      printf '    %s%s %d) %s%s\n' "$TUI_C_INK" "$mark" "$((i + 1))" "${TUI_ITEMS[$i]}" "$TUI_R"
    fi
    if [[ -n "${TUI_DESC[$i]:-}" ]]; then
      printf '       %s%s%s\n' "$TUI_C_MUTED" "${TUI_DESC[$i]}" "$TUI_R"
    fi
  done
  TUI_DRAWN=$(( ${#TUI_ITEMS[@]} + 2 ))
  local d=0
  for i in "${!TUI_DESC[@]}"; do [[ -n "${TUI_DESC[$i]:-}" ]] && d=$((d + 1)); done
  TUI_DRAWN=$(( TUI_DRAWN + d ))
}

# tui_multi <title> <var> [hint]
# Stores a comma-separated list of the chosen 1-based indices in <var>.
# Space toggles, a selects all, n clears, enter confirms.
tui_multi() {
  local title="$1" var="$2" hint="${3:-}" i answer
  local count="${#TUI_ITEMS[@]}"
  local sel=0

  if (( ! TUI_INTERACTIVE )); then
    printf '\n  %s\n' "$title"
    for i in "${!TUI_ITEMS[@]}"; do
      local mark="${TUI_OFF_GLYPH}"
      [[ "${TUI_SELECTED[$i]:-0}" == "1" ]] && mark="${TUI_ON_GLYPH}"
      printf '    %s %d) %s' "$mark" "$((i + 1))" "${TUI_ITEMS[$i]}"
      [[ -n "${TUI_DESC[$i]:-}" ]] && printf ' -- %s' "${TUI_DESC[$i]}"
      [[ "${TUI_DISABLED[$i]:-0}" == "1" ]] && printf ' (unavailable)'
      printf '\n'
    done
    printf '  Toggle numbers (comma separated), "all", "none", or blank to keep: '
    if ! IFS= read -r answer; then return 3; fi
    case "$answer" in
      q|Q) return 3 ;;
      b|B) return 1 ;;
      "") ;;
      all|ALL|a|A) for i in "${!TUI_ITEMS[@]}"; do TUI_SELECTED[$i]=1; done ;;
      none|NONE|n|N) for i in "${!TUI_ITEMS[@]}"; do TUI_SELECTED[$i]=0; done ;;
      *)
        for i in "${!TUI_ITEMS[@]}"; do TUI_SELECTED[$i]=0; done
        local -a chosen=()
        IFS=', ' read -ra chosen <<< "$answer"
        local p
        for p in "${chosen[@]}"; do
          if [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= count )); then
            TUI_SELECTED[$((p - 1))]=1
          fi
        done
        ;;
    esac
    tui_multi_result "$var"
    return 0
  fi

  tui_multi_draw "$title" "$sel"
  [[ -n "$hint" ]] && tui_hint "$hint"
  while :; do
    tui_read_key
    if (( TUI_RESIZED )); then
      TUI_RESIZED=0; tui_measure
      tui_clear; tui_wordmark; printf '\n'
      tui_multi_draw "$title" "$sel"
      [[ -n "$hint" ]] && tui_hint "$hint"
      continue
    fi
    case "$TUI_KEY" in
      up) (( sel > 0 )) && sel=$((sel - 1)) || true ;;
      down) (( sel < count - 1 )) && sel=$((sel + 1)) || true ;;
      space) if [[ "${TUI_DISABLED[$sel]:-0}" == "1" ]]; then :; elif [[ "${TUI_SELECTED[$sel]:-0}" == "1" ]]; then TUI_SELECTED[$sel]=0; else TUI_SELECTED[$sel]=1; fi ;;
      enter) printf '\n'; tui_multi_result "$var"; return 0 ;;
      back) printf '\n'; return 1 ;;
      quit) if tui_menu_confirm_quit; then return 3; fi ;;
      eof) printf '\n'; return 3 ;;
      char:a|char:A) for i in "${!TUI_ITEMS[@]}"; do TUI_SELECTED[$i]=1; done ;;
      char:n|char:N) for i in "${!TUI_ITEMS[@]}"; do TUI_SELECTED[$i]=0; done ;;
      num:*)
        local n="${TUI_KEY#num:}"
        if (( n >= 1 && n <= count )); then
          if [[ "${TUI_SELECTED[$((n - 1))]:-0}" == "1" ]]; then TUI_SELECTED[$((n - 1))]=0; else TUI_SELECTED[$((n - 1))]=1; fi
        fi
        ;;
      *) continue ;;
    esac
    printf '\e[%dA' "$TUI_DRAWN"
    tui_multi_draw "$title" "$sel"
    [[ -n "$hint" ]] && tui_hint "$hint"
  done
}

tui_multi_result() {
  local var="$1" out="" i first=1
  for i in "${!TUI_ITEMS[@]}"; do
    if [[ "${TUI_SELECTED[$i]:-0}" == "1" ]]; then
      if (( first )); then first=0; else out+=","; fi
      out+="$((i + 1))"
    fi
  done
  printf -v "$var" '%s' "$out"
}

# tui_yesno <title> <default y|n> <var>. Stores "y" or "n".
tui_yesno() {
  local title="$1" default="$2" var="$3" hint answer
  [[ "$default" == "y" ]] && hint="Y/n" || hint="y/N"
  if (( ! TUI_INTERACTIVE )); then
    printf '\n  %s [%s]: ' "$title" "$hint"
    if ! IFS= read -r answer; then return 3; fi
    case "$answer" in
      q|Q) return 3 ;;
      b|B) return 1 ;;
      "") answer="$default" ;;
      y|Y|1|yes|YES) answer="y" ;;
      n|N|0|no|NO) answer="n" ;;
      *) answer="$default" ;;
    esac
    printf -v "$var" '%s' "$answer"
    return 0
  fi
  printf '\n  %s[%s]%s ' "$TUI_BOLD" "$hint" "$TUI_R"
  IFS= read -r answer || { printf '\n'; return 3; }
  case "$answer" in
    q|Q) return 3 ;;
    b|B) return 1 ;;
    "") answer="$default" ;;
    y|Y) answer="y" ;;
    n|N) answer="n" ;;
    *) answer="$default" ;;
  esac
  printf -v "$var" '%s' "$answer"
}

# tui_input <title> <default> <var> [hint]. Free text; empty takes the default.
tui_input() {
  local title="$1" default="$2" var="$3" hint="${4:-}" answer
  if (( ! TUI_INTERACTIVE )); then
    printf '\n  %s [%s]%s: ' "$title" "$default" "${hint:+ ($hint)}"
    if ! IFS= read -r answer; then return 3; fi
    case "$answer" in q|Q) return 3 ;; b|B) return 1 ;; esac
    answer="${answer:-$default}"
  else
    printf '\n  %s%s%s %s[%s]%s ' "$TUI_BOLD" "$title" "$TUI_R" "$TUI_C_MUTED" "$default" "$TUI_R"
    IFS= read -r answer || { printf '\n'; return 3; }
    case "$answer" in
      q|Q) [[ "$answer" == "q" ]] && { printf '\n'; return 3; } ;;
      b|B) [[ "$answer" == "b" ]] && { printf '\n'; return 1; } ;;
    esac
    answer="${answer:-$default}"
  fi
  printf -v "$var" '%s' "$answer"
  return 0
}