#!/usr/bin/env bash
# aphotic safemode — bring the shell up with every plugin held back.
# @cmd: safemode
# @cmd.desc: Hold every plugin back so the shell starts as core only
# @cmd.group: LIFECYCLE
# @cmd.opt: on [--reason <text>] | Hold plugins back and note why
# @cmd.opt: off                  | Load plugins again
# @cmd.opt: status               | Whether safe mode is on, and why
#
# The flag lives in one small JSON file that services/SafeMode.qml
# watches, so this works in both directions the recovery path needs:
# turning safe mode on does not need a running shell, and turning it off
# is picked up by a running one without a restart.

_aphotic_safemode_on() {
    local reason=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reason) reason="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done

    aphotic_safe_mode_set true "$reason" || return 1
    aphotic_record_change "safe-mode-on" "$reason"
    aphotic_ok "safe mode on — plugins are held back${reason:+ (${reason})}"

    if aphotic_shell_running; then
        aphotic_log "the running shell drops them now; core surfaces are unaffected"
    else
        aphotic_log "starting the shell..."
        source "${COMMANDS_DIR}/cmd_reload.sh"
        aphotic_cmd_reload
    fi
    aphotic_log "leave it with 'aphotic safemode off'"
}

_aphotic_safemode_off() {
    if ! aphotic_safe_mode_active; then
        aphotic_log "safe mode is already off"
        return 0
    fi

    aphotic_safe_mode_set false "" || return 1
    aphotic_record_change "safe-mode-off" ""
    aphotic_ok "safe mode off — plugins load again"

    if aphotic_shell_running; then
        aphotic_log "the running shell picks them back up now"
    else
        aphotic_log "starting the shell..."
        source "${COMMANDS_DIR}/cmd_reload.sh"
        aphotic_cmd_reload
    fi
}

_aphotic_safemode_status() {
    if aphotic_safe_mode_active; then
        local reason since
        reason="$(aphotic_safe_mode_reason)"
        since="$(jq -r '.since // "unknown"' "$APHOTIC_SAFE_MODE_FILE" 2>/dev/null)"
        echo "safe mode: ON since ${since}${reason:+ — ${reason}}"
        echo "plugins held back: $(aphotic_plugin_names | wc -l)"
        echo "leave it with 'aphotic safemode off'"
    else
        echo "safe mode: off"
    fi
}

aphotic_cmd_safemode() {
    local sub="${1:-status}"
    shift || true
    case "$sub" in
        on)     _aphotic_safemode_on "$@" ;;
        off)    _aphotic_safemode_off "$@" ;;
        status) _aphotic_safemode_status ;;
        -h|--help)
            cat <<EOF
Usage: aphotic safemode <on|off|status>

  on [--reason <text>]   Hold every plugin back, note why, start the
                         shell if it is not already up
  off                    Load plugins again
  status                 Whether safe mode is on, since when, and why

Safe mode is the state 'aphotic recovery' puts a machine into when a
plugin stops the shell from starting. Core surfaces (bar, launcher,
settings, notifications) are untouched; nothing is uninstalled.
EOF
            ;;
        *)
            aphotic_err "unknown safemode subcommand: ${sub}"
            return 1
            ;;
    esac
}
