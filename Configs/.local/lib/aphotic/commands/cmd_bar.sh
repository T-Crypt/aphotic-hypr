#!/usr/bin/env bash
# aphotic bar — quick-swap the bar style without opening Settings.
# @cmd: bar
# @cmd.desc: Switch or cycle the bar style (full/dock/taskbar/minimal/capsule)
# @cmd.group: CONFIG
# @cmd.opt: style <full|dock|taskbar|minimal|capsule>  | Set the bar style
# @cmd.opt: cycle                              | Cycle to the next style
#
# Thin wrapper around the running shell's own "bar" IPC target
# (Settings.qml's setBarStyle/cycleBarStyle) -- settings.json is never
# written directly here, so the Settings tab, this CLI, and any keybind
# all stay in sync through the one function that owns the
# first-selection-position-default and pill/square memory.

_aphotic_bar_style() {
    local name="${1:-}"
    local valid=("full" "dock" "taskbar" "minimal" "capsule")

    if [[ -z "$name" ]]; then
        aphotic_err "usage: aphotic bar style <full|dock|taskbar|minimal|capsule>"
        return 1
    fi

    local ok=0
    local v
    for v in "${valid[@]}"; do
        [[ "$name" == "$v" ]] && ok=1
    done
    if [[ "$ok" -ne 1 ]]; then
        aphotic_err "unknown style '${name}' -- expected one of: ${valid[*]}"
        return 1
    fi

    aphotic_require qs || return 1
    if qs -c aphotic ipc call bar setStyle "$name"; then
        aphotic_ok "bar style set to '${name}'"
    else
        aphotic_err "failed to reach the running shell via qs ipc -- is 'qs -c aphotic' running?"
        return 1
    fi
}

_aphotic_bar_cycle() {
    aphotic_require qs || return 1
    if qs -c aphotic ipc call bar cycleStyle; then
        aphotic_ok "cycled bar style"
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
        cycle) _aphotic_bar_cycle "$@" ;;
        ""|-h|--help)
            cat <<EOF
Usage: aphotic bar <style|cycle> [args]

  style <full|dock|taskbar|minimal|capsule>   Set the bar style
  cycle                                       Cycle to the next style
EOF
            ;;
        *)
            aphotic_err "unknown bar subcommand: ${sub}"
            return 1
            ;;
    esac
}
