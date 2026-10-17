#!/usr/bin/env bash
# shellcheck disable=SC2034  # globals shared across the sourced tui modules
# lib/install/tui/screens.sh -- one function per screen.
#
# Each returns 0 to carry on, 1 to go back a screen, 2 from Review to jump
# back and edit a choice, or 3 to quit. Nothing here reaches the installer;
# the Run screen (run.sh) is the only place a changing command runs.

tui_screen_begin() {
  local idx="$1"
  tui_clear
  tui_wordmark
  printf '\n'
  tui_breadcrumb "$idx"
  printf '\n'
}

# The step line. It shows the position ("step 3 of 11") and a window of the
# flow around the current step, eliding the rest, so it fits any width down
# to the 80-column minimum. A wider terminal shows more neighbours.
tui_breadcrumb() {
  local idx="$1"
  local total="${#TUI_FLOW[@]}"
  local sep=" ${TUI_DOT} "
  local prefix="step $((idx + 1)) of $total"
  local budget=$(( TUI_COLS - 2 - ${#prefix} - ${#sep} ))
  (( budget < 1 )) && budget=1
  local lo=$idx hi=$idx best_lo=$idx best_hi=$idx j cand
  while :; do
    cand=""
    (( lo > 0 )) && cand+="${TUI_ELLIPSIS}${sep}"
    for (( j = lo; j <= hi; j++ )); do
      (( j > lo )) && cand+="$sep"
      cand+="${TUI_FLOW[$j]}"
    done
    (( hi < total - 1 )) && cand+="${sep}${TUI_ELLIPSIS}"
    (( ${#cand} <= budget )) || break
    best_lo=$lo; best_hi=$hi
    if (( hi < total - 1 )); then hi=$((hi + 1))
    elif (( lo > 0 )); then lo=$((lo - 1))
    else break
    fi
  done

  local out="  ${TUI_C_MUTED}${prefix}${TUI_R}${TUI_C_HAIR}${sep}${TUI_R}"
  (( best_lo > 0 )) && out+="${TUI_C_HAIR}${TUI_ELLIPSIS}${sep}${TUI_R}"
  local name
  for (( j = best_lo; j <= best_hi; j++ )); do
    (( j > best_lo )) && out+="${TUI_C_HAIR}${sep}${TUI_R}"
    name="${TUI_FLOW[$j]}"
    if (( j == idx )); then out+="${TUI_C_ACCENT}${TUI_BOLD}${name}${TUI_R}"
    elif (( j < idx )); then out+="${TUI_C_MUTED}${name}${TUI_R}"
    else out+="${TUI_C_HAIR}${name}${TUI_R}"; fi
  done
  (( best_hi < total - 1 )) && out+="${TUI_C_HAIR}${sep}${TUI_ELLIPSIS}${TUI_R}"
  printf '%s\n' "$out"
}

tui_flow_index() {
  local name="$1" i
  for i in "${!TUI_FLOW[@]}"; do
    [[ "${TUI_FLOW[$i]}" == "$name" ]] && { printf '%s' "$i"; return 0; }
  done
  printf '%s' "-1"
}

tui_fact() {
  printf '  %s%s%s %s\n' "$TUI_BOLD" "$(printf '%-12s' "$1")" "$TUI_R" "$(tui_fit "$2" "$((TUI_COLS - 16))")"
}

tui_step_welcome() {
  tui_screen_begin 0
  printf '\n  %sAphotic installer%s\n' "$TUI_BOLD" "$TUI_R"
  tui_hint "A guided path over install.sh. This screen reads only; nothing changes until the Run screen."
  printf '\n'
  tui_fact "System" "$TUI_DISTRO"
  tui_fact "GPU" "$TUI_GPU"
  if [[ "$TUI_HAS_INSTALL" == "1" ]]; then
    tui_fact "Aphotic" "already installed here"
  else
    tui_fact "Aphotic" "not installed"
  fi
  if [[ "$TUI_BACKUPS" != "0" ]]; then
    tui_fact "Backups" "$TUI_BACKUPS saved (latest ${TUI_BACKUP_LATEST:-unknown})"
  else
    tui_fact "Backups" "none in $(tui_backup_root)"
  fi
  tui_fact "Channel" "$TUI_CHANNEL_NOW"
  printf '\n'
  tui_hint "Uninstall and repair are separate: this path only installs. Run ./uninstall.sh to remove Aphotic."
  TUI_ITEMS=("Full install" "Config-only sync" "Dry run (preview)" "Quit")
  TUI_DESC=(
    "Everything: packages, configs, services. The normal path."
    "Copy the latest configs over ~/.config and restart the shell. No packages."
    "Print the plan install.sh would follow and change nothing."
    "Leave without changing anything."
  )
  TUI_DISABLED=(0 0 0 0)
  local choice
  local rc=0
  tui_pick "What would you like to do?" 1 choice "Arrows or j/k move, enter selects, q quits." || rc=$?
  (( rc == 0 )) || return "$rc"
  case "$choice" in
    1) TUI_MODE="full" ;;
    2) TUI_MODE="config" ;;
    3) TUI_MODE="dry" ;;
    4) return 3 ;;
  esac
  return 0
}

tui_step_channel() {
  local idx; idx="$(tui_flow_index channel)"
  tui_screen_begin "$idx"
  printf '\n  %sRelease channel%s\n' "$TUI_BOLD" "$TUI_R"
  printf '  %sCurrently on %s.%s\n' "$TUI_C_MUTED" "$TUI_CHANNEL_NOW" "$TUI_R"
  TUI_ITEMS=("Stable" "Edge")
  TUI_DESC=("Newest tagged release. Recommended." "The development branch. Newer, rougher.")
  TUI_DISABLED=(0 0)
  local default=1
  [[ "$TUI_CHANNEL_NOW" == "edge" ]] && default=2
  local choice
  local rc=0
  tui_pick "Which channel?" "$default" choice || rc=$?
  (( rc == 0 )) || return "$rc"
  [[ "$choice" == "2" ]] && TUI_CHANNEL="edge" || TUI_CHANNEL="stable"
  return 0
}

tui_step_profile() {
  local idx; idx="$(tui_flow_index profile)"
  tui_screen_begin "$idx"
  printf '\n  %sBase profile%s\n' "$TUI_BOLD" "$TUI_R"
  TUI_ITEMS=() TUI_DESC=() TUI_DISABLED=()
  local i
  for i in "${!TUI_PROFILE_NAMES[@]}"; do
    TUI_ITEMS+=("${TUI_PROFILE_NAMES[$i]}")
    TUI_DESC+=("${TUI_PROFILE_DESC[$i]}")
    TUI_DISABLED+=(0)
  done
  local default=1
  for i in "${!TUI_PROFILE_NAMES[@]}"; do
    [[ "${TUI_PROFILE_NAMES[$i]}" == "$TUI_PROFILE" ]] && default=$((i + 1))
  done
  local choice
  local rc=0
  tui_pick "Which profile?" "$default" choice || rc=$?
  (( rc == 0 )) || return "$rc"
  TUI_PROFILE="${TUI_PROFILE_NAMES[$((choice - 1))]}"
  return 0
}

tui_layers_selected_indices() {
  local i
  for i in "${!TUI_LAYER_NAMES[@]}"; do
    local n="${TUI_LAYER_NAMES[$i]}" hit=0 name
    IFS=',' read -ra _sel <<< "${TUI_LAYERS_CSV:-}"
    for name in "${_sel[@]:-}"; do [[ "$name" == "$n" ]] && hit=1; done
    printf '%s\n' "$hit"
  done
}

tui_step_layers() {
  local idx; idx="$(tui_flow_index layers)"
  tui_screen_begin "$idx"
  printf '\n  %sOptional layers%s\n' "$TUI_BOLD" "$TUI_R"
  tui_hint "None are required. Each adds its own packages; BlackArch layers are flagged."
  TUI_ITEMS=() TUI_DESC=() TUI_DISABLED=() TUI_SELECTED=()
  local i
  for i in "${!TUI_LAYER_NAMES[@]}"; do
    local name="${TUI_LAYER_NAMES[$i]}" desc="${TUI_LAYER_DESC[$i]}" tag=""
    [[ "${TUI_LAYER_BLACKARCH[$i]}" == "true" ]] && tag=" [BlackArch]"
    [[ "${TUI_LAYER_MULTILIB[$i]}" == "true" ]] && tag+=" [multilib]"
    TUI_ITEMS+=("$name$tag")
    TUI_DESC+=("$desc")
    TUI_DISABLED+=(0)
    TUI_SELECTED+=(0)
  done
  local sel_hits
  sel_hits="$(tui_layers_selected_indices)"
  i=0
  while IFS= read -r hit; do TUI_SELECTED[i]="$hit"; i=$((i + 1)); done <<< "$sel_hits"
  local picks
  local rc=0
  tui_multi "Toggle layers, enter confirms" picks "space toggles, a all, n none." || rc=$?
  (( rc == 0 )) || return "$rc"
  TUI_LAYERS_CSV="$(tui_indices_to_names "$picks" TUI_LAYER_NAMES)"
  TUI_EXPLOIT_SELECTED=0
  [[ ",$TUI_LAYERS_CSV," == *",exploit,"* || ",$TUI_LAYERS_CSV," == *",exploit-"* ]] && TUI_EXPLOIT_SELECTED=1
  return 0
}

tui_indices_to_names() {
  local picks="$1" arr_name="$2" out="" p first=1
  local -n arr="$arr_name"
  local -a plist=()
  IFS=',' read -ra plist <<< "$picks"
  for p in "${plist[@]}"; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    (( p >= 1 && p <= ${#arr[@]} )) || continue
    if (( first )); then first=0; else out+=","; fi
    out+="${arr[$((p - 1))]}"
  done
  printf '%s' "$out"
}

tui_step_theme() {
  local idx; idx="$(tui_flow_index theme)"
  tui_screen_begin "$idx"
  printf '\n  %sTheme%s\n' "$TUI_BOLD" "$TUI_R"
  TUI_ITEMS=() TUI_DESC=() TUI_DISABLED=()
  local i
  for i in "${!TUI_THEME_NAMES[@]}"; do
    local label="${TUI_THEME_DESC[$i]}"
    TUI_ITEMS+=("$label")
    if (( TUI_TRUECOLOR )) && [[ "${TUI_THEME_HAVE[$i]}" == "1" ]]; then
      TUI_DESC+=("$(tui_swatch "${TUI_THEME_BG[$i]}")$(tui_swatch "${TUI_THEME_ACCENT2[$i]}")$(tui_swatch "${TUI_THEME_ACCENT[$i]}")$(tui_swatch "${TUI_THEME_FG[$i]}")")
    else
      TUI_DESC+=("${TUI_THEME_NAMES[$i]}")
    fi
    TUI_DISABLED+=(0)
  done
  local default=1
  for i in "${!TUI_THEME_NAMES[@]}"; do
    [[ "${TUI_THEME_NAMES[$i]}" == "tokyonight" ]] && default=$((i + 1))
  done
  for i in "${!TUI_THEME_NAMES[@]}"; do
    [[ "${TUI_THEME_NAMES[$i]}" == "$TUI_THEME" ]] && default=$((i + 1))
  done
  local choice
  local rc=0
  tui_pick "Which theme?" "$default" choice || rc=$?
  (( rc == 0 )) || return "$rc"
  TUI_THEME="${TUI_THEME_NAMES[$((choice - 1))]}"
  return 0
}

tui_step_assistant() {
  local idx; idx="$(tui_flow_index assistant)"
  tui_screen_begin "$idx"
  printf '\n  %sAphotic Assistant%s\n' "$TUI_BOLD" "$TUI_R"
  tui_hint "A local chatbot. Needs an NVIDIA GPU; implies the ai layer."
  TUI_ITEMS=("Install it" "Skip it")
  TUI_DESC=("Pulls the ai layer and a local model. $( (( TUI_NVIDIA )) && echo 'NVIDIA detected.' || echo 'No NVIDIA GPU seen: not available.' )" "No chatbot. Add it later by re-running the installer.")
  if (( TUI_NVIDIA )); then TUI_DISABLED=(0 0); else TUI_DISABLED=(1 0); fi
  local default=2
  [[ "$TUI_ASSISTANT" == "on" ]] && default=1
  [[ "$TUI_ASSISTANT" == "off" ]] && default=2
  local choice
  local rc=0
  tui_pick "Assistant?" "$default" choice || rc=$?
  (( rc == 0 )) || return "$rc"
  [[ "$choice" == "1" ]] && TUI_ASSISTANT="on" || TUI_ASSISTANT="off"
  return 0
}

tui_step_display() {
  local idx; idx="$(tui_flow_index display)"
  tui_screen_begin "$idx"
  printf '\n  %sLogin screen%s\n' "$TUI_BOLD" "$TUI_R"
  TUI_ITEMS=("Aphotic greeter (greetd)" "Keep SDDM")
  TUI_DESC=("Aphotic's own login screen. The default." "Leave the login screen you already have.")
  TUI_DISABLED=(0 0)
  local default=1
  (( TUI_KEEP_SDDM )) && default=2
  local choice
  local rc=0
  tui_pick "Which login screen?" "$default" choice || rc=$?
  (( rc == 0 )) || return "$rc"
  [[ "$choice" == "2" ]] && TUI_KEEP_SDDM=1 || TUI_KEEP_SDDM=0
  return 0
}

tui_step_nvidia() {
  local idx; idx="$(tui_flow_index nvidia)"
  tui_screen_begin "$idx"
  printf '\n  %sNVIDIA driver%s\n' "$TUI_BOLD" "$TUI_R"
  tui_hint "A driver is already present. Keep it, or replace it with Aphotic's recommended nvidia-open-dkms."
  TUI_ITEMS=("Keep the existing driver" "Reinstall with nvidia-open-dkms")
  TUI_DESC=("Never touches a working driver." "Uninstalls what is there first, then installs nvidia-open-dkms.")
  TUI_DISABLED=(0 0)
  local default=1
  [[ "$TUI_NVIDIA_ACTION" == "reinstall" ]] && default=2
  local choice
  local rc=0
  tui_pick "Driver action?" "$default" choice || rc=$?
  (( rc == 0 )) || return "$rc"
  [[ "$choice" == "2" ]] && TUI_NVIDIA_ACTION="reinstall" || TUI_NVIDIA_ACTION="keep"
  return 0
}

tui_step_conflicts() {
  local idx; idx="$(tui_flow_index conflicts)"
  tui_screen_begin "$idx"
  printf '\n  %sConflicting packages%s\n' "$TUI_BOLD" "$TUI_R"
  tui_hint "Aphotic replaces some tools (waybar, rofi/wofi, dunst/mako/swaync)."
  TUI_ITEMS=("Let the installer choose" "Remove them" "Leave them installed")
  TUI_DESC=("The installer's own interactive question." "Remove the packages Aphotic replaces." "Keep them; Aphotic still installs.")
  TUI_DISABLED=(0 0 0)
  local default=1
  [[ "$TUI_CONFLICTS" == "strip" ]] && default=2
  [[ "$TUI_CONFLICTS" == "keep" ]] && default=3
  local choice
  local rc=0
  tui_pick "What should happen to them?" "$default" choice || rc=$?
  (( rc == 0 )) || return "$rc"
  case "$choice" in
    1) TUI_CONFLICTS="" ;;
    2) TUI_CONFLICTS="strip" ;;
    3) TUI_CONFLICTS="keep" ;;
  esac
  return 0
}

tui_step_backup() {
  local idx; idx="$(tui_flow_index backup)"
  tui_screen_begin "$idx"
  printf '\n  %sBackup%s\n' "$TUI_BOLD" "$TUI_R"
  local do_backup
  local default="y"
  (( TUI_NO_BACKUP )) && default="n"
  local rc=0
  tui_yesno "Back up existing configs before copying Aphotic's?" "$default" do_backup || rc=$?
  (( rc == 0 )) || return "$rc"
  if [[ "$do_backup" == "y" ]]; then
    TUI_NO_BACKUP=0
    local count
    tui_input "How many backups to keep?" "$TUI_KEEP_BACKUPS" count "a number" || rc=$?
    (( rc == 0 )) || return "$rc"
    [[ "$count" =~ ^[0-9]+$ ]] && TUI_KEEP_BACKUPS="$count"
  else
    TUI_NO_BACKUP=1
  fi
  return 0
}

tui_step_exploit() {
  local idx; idx="$(tui_flow_index exploit)"
  tui_screen_begin "$idx"
  printf '\n  %sSecurity tools disclaimer%s\n' "$TUI_BOLD" "$TUI_R"
  printf '  %sUse these tools only on systems you own or have written permission to test.%s\n' "$TUI_C_WARN" "$TUI_R"
  local accept
  local rc=0
  tui_yesno "I have read that and agree" "y" accept || rc=$?
  (( rc == 0 )) || return "$rc"
  [[ "$accept" == "y" ]] && TUI_ACCEPT_EXPLOIT=1 || TUI_ACCEPT_EXPLOIT=0
  return 0
}

tui_step_review() {
  local idx; idx="$(tui_flow_index review)"
  tui_build_argv
  tui_screen_begin "$idx"
  printf '\n  %sReview%s\n' "$TUI_BOLD" "$TUI_R"
  printf '  %sinstall.sh command line (copyable):%s\n\n' "$TUI_C_MUTED" "$TUI_R"
  tui_wrap "$(tui_cmdline)" 4 "$TUI_C_INK"
  printf '\n'
  printf '  %sWhat each choice means:%s\n\n' "$TUI_C_MUTED" "$TUI_R"
  TUI_REVIEW_STEPS=()
  local n=0
  _add() {
    TUI_REVIEW_STEPS+=("$1"); n=$((n + 1))
    local pfx="    $n) "
    printf '    %s%s)%s ' "$TUI_C_INK" "$n" "$TUI_R"
    tui_wrap_prefixed "${#pfx}" "$2"
  }
  _add channel "Channel: $TUI_CHANNEL"
  if [[ "$TUI_MODE" != "config" ]]; then
    _add profile "Profile: $TUI_PROFILE"
    _add layers "Layers: $([[ -n "$TUI_LAYERS_CSV" ]] && echo "$TUI_LAYERS_CSV" || echo none)"
    _add theme "Theme: $TUI_THEME"
    _add assistant "Assistant: $TUI_ASSISTANT"
    _add display "Login screen: $( (( TUI_KEEP_SDDM )) && echo 'keep SDDM' || echo 'Aphotic greeter' )"
    if (( TUI_NVIDIA )); then _add nvidia "NVIDIA driver: $TUI_NVIDIA_ACTION"; fi
    _add conflicts "Conflicts: ${TUI_CONFLICTS:-installer asks}"
    _add backup "Backup: $( (( TUI_NO_BACKUP )) && echo off || echo "on, keep $TUI_KEEP_BACKUPS" )"
    if (( TUI_EXPLOIT_SELECTED )); then _add exploit "Security disclaimer: $([[ "$TUI_ACCEPT_EXPLOIT" == "1" ]] && echo accepted || echo 'not accepted')"; fi
  else
    _add profile "Config-only: reuses the saved profile, layers and theme."
  fi
  unset -f _add
  printf '\n'
  tui_hint "enter runs it, b goes back, or a number edits that item."
  local answer
  if (( TUI_INTERACTIVE )); then
    printf '\n  %srun?%s %s' "$TUI_BOLD" "$TUI_R" ""
    tui_read_key
    case "$TUI_KEY" in
      enter) printf '\n'; return 0 ;;
      back) printf '\n'; return 1 ;;
      quit) printf '\n'; return 3 ;;
      num:*)
        printf '\n'
        n="${TUI_KEY#num:}"
        if (( n >= 1 && n <= ${#TUI_REVIEW_STEPS[@]} )); then
          local target
          target="$(tui_flow_index "${TUI_REVIEW_STEPS[$((n - 1))]}")"
          if (( target >= 0 )); then TUI_REVIEW_TARGET="$target"; return 2; fi
        fi
        return 0
        ;;
      *) printf '\n'; return 0 ;;
    esac
  fi
  printf '  r=run, b=back, or a number to edit: '
  if ! IFS= read -r answer; then printf '\n'; return 3; fi
  printf '\n'
  case "$answer" in
    ""|r|R|run) return 0 ;;
    b|B) return 1 ;;
    q|Q) return 3 ;;
    *[!0-9]*) return 0 ;;
    *)
      if (( answer >= 1 && answer <= ${#TUI_REVIEW_STEPS[@]} )); then
        local target
        target="$(tui_flow_index "${TUI_REVIEW_STEPS[$((answer - 1))]}")"
        if (( target >= 0 )); then TUI_REVIEW_TARGET="$target"; return 2; fi
      fi
      return 0
      ;;
  esac
}

# The exact argv install.sh will receive, shown on Review and used by Run.
# Values come from validated enums and repo filenames, so they carry no
# spaces and print as-is.
tui_cmdline() {
  printf './install.sh'
  local a
  for a in "${TUI_ARGV[@]}"; do printf ' %s' "$a"; done
}