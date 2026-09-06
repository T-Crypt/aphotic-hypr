#!/usr/bin/env bash
# aphotic recovery — diagnose a shell that will not start, and get out of it.
# @cmd: recovery
# @cmd.desc: Diagnose repeated shell startup failures and recover from them
# @cmd.group: LIFECYCLE
# @cmd.opt: status [--json]  | What failed, how often, and what is suspected
# @cmd.opt: present          | Show the recovery surface (or a terminal menu)
# @cmd.opt: menu             | The terminal menu on its own
# @cmd.opt: apply <action>   | disable-suspect | safe-mode | restore-last | continue
# @cmd.opt: record <r> <s>   | Record a unit exit (called by aphotic-shell.service)
# @cmd.opt: clear            | Forget the recorded failures
#
# aphotic-shell.service records every failed exit here (ExecStopPost) and
# fires `recovery present` once systemd gives up restarting (OnFailure,
# i.e. StartLimitBurst exceeded). That is the whole trigger: nothing
# polls, and a shell that crashes once and comes back never reaches this.
#
# Everything below has to work with no shell running at all, so the
# diagnosis lives here in bash and both front ends -- the quickshell
# recovery surface and the terminal menu -- read it from `status --json`.

APHOTIC_RECOVERY_KEEP=10

# ---- recording -------------------------------------------------------

_aphotic_recovery_record() {
    local result="${1:-unknown}" status="${2:-}" tmp
    # A clean stop is a restart or a logout, not a failure.
    [[ "$result" == "success" ]] && return 0
    command -v jq >/dev/null 2>&1 || return 0

    [[ -f "$APHOTIC_RECOVERY_STATE_FILE" ]] || echo '{"failures": []}' > "$APHOTIC_RECOVERY_STATE_FILE"
    tmp="$(mktemp)"
    jq --arg at "$(date -Iseconds)" \
       --arg result "$result" \
       --arg status "$status" \
       --argjson keep "$APHOTIC_RECOVERY_KEEP" \
       '.failures = ((.failures // []) + [{at: $at, result: $result, status: $status}] | .[-$keep:])' \
       "$APHOTIC_RECOVERY_STATE_FILE" > "$tmp" && mv "$tmp" "$APHOTIC_RECOVERY_STATE_FILE"
    return 0
}

_aphotic_recovery_clear() {
    echo '{"failures": []}' > "$APHOTIC_RECOVERY_STATE_FILE"
    systemctl --user reset-failed aphotic-shell.service >/dev/null 2>&1 || true
}

_aphotic_recovery_failure_count() {
    [[ -f "$APHOTIC_RECOVERY_STATE_FILE" ]] || { echo 0; return 0; }
    jq -r '(.failures // []) | length' "$APHOTIC_RECOVERY_STATE_FILE" 2>/dev/null || echo 0
}

# ---- evidence --------------------------------------------------------

# Whatever the last attempt printed. The service path logs to the
# journal, a hand-started daemon to shell.log; try both rather than
# assuming which one this machine uses.
_aphotic_recovery_log_tail() {
    local lines="${1:-200}" out=""
    if command -v journalctl >/dev/null 2>&1; then
        out="$(journalctl --user -u aphotic-shell.service -n "$lines" --no-pager -o cat 2>/dev/null || true)"
    fi
    if [[ -z "${out// /}" && -f "${APHOTIC_STATE_HOME}/shell.log" ]]; then
        out="$(tail -n "$lines" "${APHOTIC_STATE_HOME}/shell.log" 2>/dev/null || true)"
    fi
    printf '%s\n' "$out"
}

# The strongest evidence there is: the failure output naming a file under
# a plugin's own directory. Asked the other way round -- for each
# installed plugin, does the output mention its directory -- so a stray
# path in an unrelated line cannot invent a plugin that is not there, and
# so no path escaping is involved. Core never names a plugin
# (ARCHITECTURE section 3 rule 9); this reads one out of the crash.
#
# Latest mention wins. QML reports the failing component last, after
# whatever loaded fine before it.
_aphotic_recovery_suspect_plugin() {
    local log name line best="" best_line=0

    log="$(_aphotic_recovery_log_tail)"
    [[ -n "${log//[[:space:]]/}" ]] || return 1

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        line="$(printf '%s\n' "$log" | grep -nF -- "${APHOTIC_PLUGINS_DIR}/${name}/" | tail -n 1 | cut -d: -f1)"
        [[ -n "$line" ]] || continue
        if [[ "$line" -ge "$best_line" ]]; then
            best_line="$line"
            best="$name"
        fi
    done < <(aphotic_plugin_names)

    [[ -n "$best" ]] || return 1
    printf '%s\n' "$best"
}

# Fallback when the crash names nothing: what changed most recently.
# A shell that stopped starting right after a plugin went in is the
# common case, and the ordering is the only evidence available.
_aphotic_recovery_last_change() {
    [[ -f "$APHOTIC_CHANGE_LOG" ]] || return 0
    tail -n 1 "$APHOTIC_CHANGE_LOG" 2>/dev/null || true
}

_aphotic_recovery_latest_backup() {
    [[ -d "$APHOTIC_BACKUP_DIR" ]] || return 0
    find "$APHOTIC_BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null \
        | sort | tail -n 1
}

_aphotic_recovery_unit_state() {
    systemctl --user is-active aphotic-shell.service 2>/dev/null || true
}

# ---- status ----------------------------------------------------------

_aphotic_recovery_status_json() {
    aphotic_require jq || return 1
    local suspect last_change backup safe_mode

    suspect="$(_aphotic_recovery_suspect_plugin || true)"
    last_change="$(_aphotic_recovery_last_change)"
    backup="$(_aphotic_recovery_latest_backup)"
    safe_mode=false
    aphotic_safe_mode_active && safe_mode=true

    jq -n \
        --arg unit "$(_aphotic_recovery_unit_state)" \
        --argjson failures "$(_aphotic_recovery_failure_count)" \
        --arg suspectPlugin "$suspect" \
        --arg lastChange "$last_change" \
        --arg latestBackup "$backup" \
        --argjson safeMode "$safe_mode" \
        --arg logTail "$(_aphotic_recovery_log_tail 40)" \
        --arg version "$APHOTIC_VERSION" \
        '{unit: $unit, failures: $failures, suspectPlugin: $suspectPlugin,
          lastChange: $lastChange, latestBackup: $latestBackup,
          safeMode: $safeMode, logTail: $logTail, version: $version}'
}

_aphotic_recovery_status_text() {
    local suspect last_change backup

    echo "Aphotic recovery — aphotic ${APHOTIC_VERSION}"
    echo
    printf '  shell unit:        %s\n' "$(_aphotic_recovery_unit_state)"
    printf '  recorded failures: %s\n' "$(_aphotic_recovery_failure_count)"
    printf '  safe mode:         %s\n' "$(aphotic_safe_mode_active && echo on || echo off)"

    suspect="$(_aphotic_recovery_suspect_plugin || true)"
    if [[ -n "$suspect" ]]; then
        printf '  suspected plugin:  %s (named in the failure output)\n' "$suspect"
    else
        printf '  suspected plugin:  none named in the failure output\n'
    fi

    last_change="$(_aphotic_recovery_last_change)"
    [[ -n "$last_change" ]] && printf '  last change:       %s\n' "$last_change"

    backup="$(_aphotic_recovery_latest_backup)"
    [[ -n "$backup" ]] && printf '  latest backup:     %s\n' "$backup"

    echo
    echo "Last output:"
    _aphotic_recovery_log_tail 20 | sed 's/^/  /'
}

# ---- actions ---------------------------------------------------------

# systemd refuses to start a unit that tripped its own start limit until
# the failure is cleared, so every action has to reset it before asking
# for a restart -- otherwise the fix applies and the shell still does not
# come up. Restart itself goes through `aphotic reload`, which is already
# the single answer to "restart the shell" (orphan kill included).
_aphotic_recovery_restart_shell() {
    systemctl --user reset-failed aphotic-shell.service >/dev/null 2>&1 || true
    source "${COMMANDS_DIR}/cmd_reload.sh"
    aphotic_cmd_reload
}

_aphotic_recovery_apply() {
    local action="${1:-}"

    case "$action" in
        disable-suspect)
            local suspect
            suspect="$(_aphotic_recovery_suspect_plugin || true)"
            if [[ -z "$suspect" ]]; then
                aphotic_err "nothing to disable: the failure output does not name a plugin"
                aphotic_log "try 'aphotic recovery apply safe-mode' to hold all of them back instead"
                return 1
            fi
            source "${COMMANDS_DIR}/cmd_plugin.sh"
            aphotic_cmd_plugin disable "$suspect" || return 1
            aphotic_record_change "recovery-disabled-plugin" "$suspect"
            ;;
        safe-mode)
            source "${COMMANDS_DIR}/cmd_safemode.sh"
            aphotic_safe_mode_set true "repeated startup failures" || return 1
            aphotic_record_change "safe-mode-on" "recovery"
            aphotic_ok "safe mode on — plugins are held back"
            ;;
        restore-last)
            local backup
            backup="$(_aphotic_recovery_latest_backup)"
            if [[ -z "$backup" ]]; then
                aphotic_err "no backup to restore (see 'aphotic backup list')"
                return 1
            fi
            source "${COMMANDS_DIR}/cmd_backup.sh"
            _aphotic_backup_revert --yes "$backup" || return 1
            aphotic_record_change "recovery-restored-backup" "$backup"
            ;;
        continue)
            aphotic_log "starting the shell unchanged"
            ;;
        ""|-h|--help)
            aphotic_err "usage: aphotic recovery apply <disable-suspect|safe-mode|restore-last|continue>"
            return 1
            ;;
        *)
            aphotic_err "unknown recovery action: ${action}"
            return 1
            ;;
    esac

    _aphotic_recovery_clear
    _aphotic_recovery_restart_shell
}

# ---- front ends ------------------------------------------------------

_aphotic_recovery_menu() {
    local suspect backup choice

    _aphotic_recovery_status_text
    suspect="$(_aphotic_recovery_suspect_plugin || true)"
    backup="$(_aphotic_recovery_latest_backup)"

    echo
    echo "What would you like to do?"
    echo "  1) Disable ${suspect:-the suspected plugin}${suspect:+ and restart}"
    echo "  2) Start in safe mode (every plugin held back)"
    echo "  3) Restore the last backup${backup:+ (${backup})}"
    echo "  4) Start normally and leave everything alone"
    echo "  5) Do nothing for now"
    echo
    read -r -p "Choice [1-5]: " choice

    case "$choice" in
        1) _aphotic_recovery_apply disable-suspect ;;
        2) _aphotic_recovery_apply safe-mode ;;
        3) _aphotic_recovery_apply restore-last ;;
        4) _aphotic_recovery_apply continue ;;
        *) aphotic_log "nothing changed — run 'aphotic recovery menu' again when you are ready" ;;
    esac
}

# Last resort when the recovery surface itself cannot render: the user's
# terminal, running the same menu. Worth having -- if quickshell or Qt is
# what broke, a second quickshell config does not help.
_aphotic_recovery_terminal() {
    local term
    for term in kitty foot alacritty wezterm xterm; do
        command -v "$term" >/dev/null 2>&1 || continue
        setsid "$term" -e aphotic recovery menu >/dev/null 2>&1 &
        disown
        return 0
    done
    aphotic_err "no terminal found to show the recovery menu in; run 'aphotic recovery menu' yourself"
    return 1
}

_aphotic_recovery_present() {
    local lock="${APHOTIC_RUNTIME_DIR}/recovery.pid" pid config

    # Nothing good comes of two recovery surfaces stacked on one screen,
    # and OnFailure can fire again while the first is still open.
    if [[ -f "$lock" ]] && kill -0 "$(cat "$lock" 2>/dev/null || echo 0)" 2>/dev/null; then
        aphotic_log "a recovery surface is already open"
        return 0
    fi

    config="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/aphotic-recovery"
    if command -v qs >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]] && [[ -d "$config" ]]; then
        setsid qs -c aphotic-recovery >> "${APHOTIC_STATE_HOME}/recovery.log" 2>&1 &
        pid=$!
        disown
        echo "$pid" > "$lock"
        # It either renders or it does not; three seconds is long enough
        # to tell a running surface from a config that failed to load.
        sleep 3
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        rm -f "$lock"
        aphotic_warn "the recovery surface would not start either — falling back to a terminal"
    fi

    _aphotic_recovery_terminal
}

aphotic_cmd_recovery() {
    local sub="${1:-status}"
    shift || true
    case "$sub" in
        record)  _aphotic_recovery_record "${1:-}" "${2:-}" ;;
        status)
            if [[ "${1:-}" == "--json" ]]; then
                _aphotic_recovery_status_json
            else
                _aphotic_recovery_status_text
            fi
            ;;
        present) _aphotic_recovery_present ;;
        menu)    _aphotic_recovery_menu ;;
        apply)   _aphotic_recovery_apply "${1:-}" ;;
        clear)   _aphotic_recovery_clear && aphotic_ok "recorded failures cleared" ;;
        -h|--help)
            cat <<EOF
Usage: aphotic recovery <status|present|menu|apply|clear> [args]

  status [--json]   What failed, how often, what is suspected
  present           Show the recovery surface, or a terminal menu if it
                    cannot render (SUPER+SHIFT+R, and what
                    aphotic-recovery.service runs)
  menu              The terminal menu on its own
  apply <action>    disable-suspect | safe-mode | restore-last | continue
  clear             Forget the recorded failures

aphotic-shell.service records failed exits and fires 'present' once
systemd stops retrying. See docs/playbooks/safe-mode-recovery.md.
EOF
            ;;
        *)
            aphotic_err "unknown recovery subcommand: ${sub}"
            return 1
            ;;
    esac
}
