#!/usr/bin/env bash
# aphotic bar — quick-swap the bar layout or corners without opening Settings.
# @cmd: bar
# @cmd.desc: Set or cycle the bar layout, or set its corner style (full/capsule/dock/taskbar/minimal)
# @cmd.group: CONFIG
# @cmd.opt: style <full|capsule|dock|taskbar|minimal>  | Set the bar layout
# @cmd.opt: corners <sharp|soft|round>                 | Set the bar corner style
# @cmd.opt: cycle                              | Cycle to the next layout
#
# Thin wrapper around the running shell's own "bar" IPC target
# (Settings.qml's setBarStyle/setCorners/cycleBarStyle) -- settings.json
# is never written directly here, so the Settings tab, this CLI, and any
# keybind all stay in sync through the one function that owns the
# first-selection-position-default bookkeeping.

_aphotic_bar_style() {
    local name="${1:-}"
    local valid=("full" "capsule" "dock" "taskbar" "minimal")

    if [[ -z "$name" ]]; then
        aphotic_err "usage: aphotic bar style <full|capsule|dock|taskbar|minimal>"
        return 1
    fi

    local ok=0
    local v
    for v in "${valid[@]}"; do
        [[ "$name" == "$v" ]] && ok=1
    done
    if [[ "$ok" -ne 1 ]]; then
        aphotic_err "unknown layout '${name}' -- expected one of: ${valid[*]}"
        return 1
    fi

    aphotic_require qs || return 1
    if qs -c aphotic ipc call bar setStyle "$name"; then
        aphotic_ok "bar layout set to '${name}'"
    else
        aphotic_err "failed to reach the running shell via qs ipc -- is 'qs -c aphotic' running?"
        return 1
    fi
}

_aphotic_bar_corners() {
    local name="${1:-}"
    local valid=("sharp" "soft" "round")

    if [[ -z "$name" ]]; then
        aphotic_err "usage: aphotic bar corners <sharp|soft|round>"
        return 1
    fi

    local ok=0
    local v
    for v in "${valid[@]}"; do
        [[ "$name" == "$v" ]] && ok=1
    done
    if [[ "$ok" -ne 1 ]]; then
        aphotic_err "unknown corner style '${name}' -- expected one of: ${valid[*]}"
        return 1
    fi

    aphotic_require qs || return 1
    if qs -c aphotic ipc call bar setCorners "$name"; then
        aphotic_ok "bar corners set to '${name}'"
    else
        aphotic_err "failed to reach the running shell via qs ipc -- is 'qs -c aphotic' running?"
        return 1
    fi
}

_aphotic_bar_cycle() {
    aphotic_require qs || return 1
    if qs -c aphotic ipc call bar cycleStyle; then
        aphotic_ok "cycled bar layout"
    else
        aphotic_err "failed to reach the running shell via qs ipc -- is 'qs -c aphotic' running?"
        return 1
    fi
}

aphotic_cmd_bar() {
    local sub="${1:-}"
    shift || true
    case "$sub" in
        style) _aphotic_bar_style "$@" ;;
        corners) _aphotic_bar_corners "$@" ;;
        cycle) _aphotic_bar_cycle "$@" ;;
        ""|-h|--help)
            cat <<EOF
Usage: aphotic bar <style|corners|cycle> [args]

  style <full|capsule|dock|taskbar|minimal>   Set the bar layout
  corners <sharp|soft|round>                  Set the bar corner style
  cycle                                       Cycle to the next layout
EOF
            ;;
        *)
            aphotic_err "unknown bar subcommand: ${sub}"
            return 1
            ;;
    esac
}
