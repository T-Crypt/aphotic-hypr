#!/usr/bin/env bash
# shellcheck disable=SC2034  # globals shared across the sourced tui modules
# lib/install/tui/run.sh -- the Run and Finish screens.
#
# This is the only file that runs the installer or touches sudo, and only
# after the Review screen says so. Stage progress comes from install.sh's
# own TOTAL_STAGES/STAGE_COLORS, read here without sourcing it.

# Side-effect-free: sed runs against the file's text, never executes it.
tui_load_stages() {
  TUI_TOTAL_STAGES="$(sed -n 's/^TOTAL_STAGES=//p' "$TUI_ROOT/install.sh" | head -n1)"
  TUI_TOTAL_STAGES="${TUI_TOTAL_STAGES:-7}"
  local line
  line="$(sed -n 's/^STAGE_COLORS=//p' "$TUI_ROOT/install.sh" | head -n1)"
  line="${line#\(}"; line="${line%\)}"
  TUI_STAGE_COLORS=()
  read -ra TUI_STAGE_COLORS <<< "$line"
}

tui_stage_color() {
  local n="${1:-1}" count="${#TUI_STAGE_COLORS[@]}"
  (( count > 0 )) || { printf '36'; return 0; }
  printf '%s' "${TUI_STAGE_COLORS[$(((n - 1) % count))]}"
}

# sudo reads the password from the terminal itself, before any logging
# starts. The wrapper never prompts for, echoes, or logs a password.
tui_sudo_upfront() {
  [[ "${TUI_NO_SUDO:-0}" == "1" ]] && return 0
  [[ -t 0 ]] || return 0
  command -v sudo >/dev/null 2>&1 || return 0
  tui_note muted "Checking sudo access (sudo asks, not this wrapper)."
  printf '\n'
  sudo -v || { tui_note err "sudo access is required to install."; return 1; }
  (
    while kill -0 "$$" 2>/dev/null; do
      sudo -n true 2>/dev/null || exit 0
      sleep 50
    done
  ) &
  TUI_SUDO_KEEPALIVE=$!
  return 0
}

tui_log_pane() {
  printf '%s%s%s\n' "$TUI_C_MUTED" "$(tui_fit "--- $(pwd)/install.log (last $TUI_LOG_LINES lines) ---" "$TUI_COLS")" "$TUI_R"
  if [[ -f install.log ]]; then
    tail -n "$TUI_LOG_LINES" install.log
  else
    printf '(no install.log yet)\n'
  fi
}

tui_stage_from_line() {
  local line="$1"
  if [[ "$line" =~ \[([0-9]+)/[0-9]+\] ]]; then
    TUI_STAGE_INDEX="${BASH_REMATCH[1]}"
  fi
}

tui_handle_line() {
  local line="$1"
  tui_stage_from_line "$line"
  printf '%s\n' "$line" >> install.log
  TUI_RING+=("$line")
  local max="$TUI_LOG_LINES"
  while (( ${#TUI_RING[@]} > max )); do TUI_RING=("${TUI_RING[@]:1}"); done
  if (( TUI_INTERACTIVE )); then
    tui_render_run
  else
    printf '%s\n' "$line"
  fi
}

tui_elapsed() {
  local now
  now="$(date +%s)"
  printf '%s' "$(( now - TUI_RUN_START ))"
}

tui_render_run() {
  local lit done_stages
  if (( TUI_RESIZED )); then TUI_RESIZED=0; tui_measure; fi
  done_stages=$(( TUI_STAGE_INDEX > 0 ? TUI_STAGE_INDEX - 1 : 0 ))
  lit=$(( TUI_COLS * done_stages / TUI_TOTAL_STAGES ))
  tui_clear
  tui_wordmark
  printf '\n'
  printf '  %sRunning:%s\n' "$TUI_BOLD" "$TUI_R"
  tui_wrap "$(tui_cmdline)" 4 "$TUI_C_MUTED"
  printf '  %sStage %s/%s%s  %s%ss elapsed%s\n' "$TUI_C_MUTED" "$TUI_STAGE_INDEX" "$TUI_TOTAL_STAGES" "$TUI_R" "$TUI_C_MUTED" "$(tui_elapsed)" "$TUI_R"
  printf '  %s' "$TUI_C_LIVE"
  tui_rule "$lit"
  printf '\n  %s--- live log ---%s\n' "$TUI_C_MUTED" "$TUI_R"
  local l
  for l in "${TUI_RING[@]}"; do printf '  %s\n' "$l"; done
  tui_hint "Ctrl-C to abort (it asks first)."
}

tui_run_installer() {
  TUI_RUN_START="$(date +%s)"
  TUI_STAGE_INDEX=0
  TUI_RING=()
  TUI_FIFO="$(mktemp -u "${TMPDIR:-/tmp}/aphotic-tui.XXXXXX")"
  if ! mkfifo "$TUI_FIFO"; then
    tui_note err "Could not create a pipe for the installer output."
    return 1
  fi
  printf '  %sRunning%s\n' "$TUI_BOLD" "$TUI_R"
  tui_wrap "$(tui_cmdline)" 4 "$TUI_C_MUTED"
  "$TUI_INSTALL_SH" "${TUI_ARGV[@]}" > "$TUI_FIFO" 2>&1 &
  TUI_CHILD=$!
  exec 3< "$TUI_FIFO"
  TUI_RUNNING=1
  local line status=0
  if (( TUI_INTERACTIVE )); then tui_render_run; fi
  while kill -0 "$TUI_CHILD" 2>/dev/null; do
    if IFS= read -r -t 0.5 line <&3; then
      tui_handle_line "$line"
    elif (( TUI_INTERACTIVE )); then
      tui_render_run
    fi
  done
  while IFS= read -r line <&3; do tui_handle_line "$line"; done
  exec 3<&-
  wait "$TUI_CHILD" || status=$?
  TUI_CHILD=0
  TUI_RUNNING=0
  rm -f "$TUI_FIFO"
  TUI_FIFO=""
  if (( ! TUI_INTERACTIVE )); then
    printf '\n'
    tui_log_pane
  fi
  return "$status"
}

tui_finish() {
  local status="$1"
  tui_clear
  tui_wordmark
  printf '\n'
  if (( status == 0 )); then
    printf '  %sInstall finished.%s\n' "$TUI_C_OK" "$TUI_R"
    tui_wrap "Elapsed $(tui_elapsed)s. Log: $(pwd)/install.log" 2 "$TUI_C_MUTED"
    printf '\n'
    printf '  %sNext steps%s\n' "$TUI_BOLD" "$TUI_R"
    printf '    %sLog out and back in, or reboot, so the new session starts.%s\n' "$TUI_C_INK" "$TUI_R"
    printf '    %sSession menu: Super+Backspace%s\n' "$TUI_C_MUTED" "$TUI_R"
    printf '    %sOpen settings: Super+I%s\n' "$TUI_C_MUTED" "$TUI_R"
    printf '    %sKeybind cheatsheet: Super+K%s\n' "$TUI_C_MUTED" "$TUI_R"
    printf '    %sChange theme: Super+, or Super+.%s\n' "$TUI_C_MUTED" "$TUI_R"
    printf '    %sUpdate later: aphotic update%s\n' "$TUI_C_MUTED" "$TUI_R"
    printf '    %sRemove Aphotic: ./uninstall.sh%s\n' "$TUI_C_MUTED" "$TUI_R"
    if (( TUI_NVIDIA )) && [[ "$TUI_MODE" != "config" ]]; then
      printf '\n'
      tui_note warn "An NVIDIA driver was set up. A reboot is expected before it is used."
    fi
  else
    printf '  %sInstall did not finish (exit %s).%s\n' "$TUI_C_ERR" "$status" "$TUI_R"
    tui_wrap "Log: $(pwd)/install.log" 2 "$TUI_C_MUTED"
    tui_wrap "Report it: ${APHOTIC_ISSUES_URL:-https://github.com/T-Crypt/Aphotic-Hypr/issues}" 2 "$TUI_C_MUTED"
    tui_wrap "install.sh prints its own redacted failure report and offers to file it when it can." 2 "$TUI_C_MUTED"
  fi
  printf '\n'
  return "$status"
}