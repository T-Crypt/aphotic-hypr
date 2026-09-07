#!/usr/bin/env bash
# aphotic reconcile — converge installed plugins to match aphotic.toml's
# [plugins] enabled list. Dry-run by default; --apply actually converges.
#
# Scope is deliberately narrow: plugins are the only domain with a real
# user-declared desired state today (aphotic.toml's [plugins] section).
# --apply only ever toggles enable/disable on plugins already installed
# -- it never installs a plugin it doesn't have (that's a network fetch
# with its own failure modes, not a flip of a flag) and never touches
# packages (needs sudo and a resolved profile, install.sh's job, same
# boundary `aphotic sync` already respects). A "missing" plugin is
# reported with the command to install it, not run automatically.
# Daemon/display-manager drift is informational only -- there's no
# [services] section declaring a "should be" state to converge against.
# @cmd: reconcile
# @cmd.desc: Converge installed plugins to match aphotic.toml's [plugins] list
# @cmd.group: LIFECYCLE
# @cmd.opt: (no args) | Dry run: show what would change
# @cmd.opt: --apply    | Enable/disable plugins to match aphotic.toml (auto-snapshots first)
# @cmd.opt: --json     | Machine-readable report

aphotic_cmd_reconcile() {
    source "${LIB_DIR}/state.sh"

    local apply=0 as_json=0
    for arg in "$@"; do
        case "$arg" in
            --apply) apply=1 ;;
            --json) as_json=1 ;;
            -h|--help)
                cat <<'HELP'
Usage: aphotic reconcile [--apply] [--json]

Compares the plugin registry against aphotic.toml's [plugins] enabled
list. With no flags, prints what would change (a dry run) -- nothing is
touched. --apply enables/disables plugins to match, snapshotting first
(aphotic backup create --label pre-reconcile) so aphotic rollback can
undo it. A plugin that isn't installed at all is reported, not
installed -- run the printed 'aphotic plugin install' command yourself.
Packages aren't touched here either; see 'aphotic diff'/'aphotic sync'.
HELP
                return 0
                ;;
        esac
    done

    if ! _aphotic_state_plugins_declared; then
        if [[ "$as_json" -eq 1 ]]; then
            jq -nc '{declared: false, missing: [], toEnable: [], toDisable: [], applied: false}'
        else
            aphotic_log "no [plugins] section in aphotic.toml -- nothing declared, nothing to reconcile"
        fi
        return 0
    fi

    local missing=() to_enable=() to_disable=() name state
    while IFS=$'\t' read -r name state; do
        [[ -z "$name" ]] && continue
        case "$state" in
            missing) missing+=("$name") ;;
            disabled) to_enable+=("$name") ;;
            extra) to_disable+=("$name") ;;
        esac
    done < <(_aphotic_state_plugin_drift)

    local applicable=$((${#to_enable[@]} + ${#to_disable[@]}))
    local total=$((applicable + ${#missing[@]}))

    if [[ "$as_json" -eq 1 && "$apply" -eq 0 ]]; then
        local missing_json="[]" enable_json="[]" disable_json="[]"
        [[ "${#missing[@]}" -gt 0 ]] && missing_json="$(printf '%s\n' "${missing[@]}" | jq -R . | jq -sc .)"
        [[ "${#to_enable[@]}" -gt 0 ]] && enable_json="$(printf '%s\n' "${to_enable[@]}" | jq -R . | jq -sc .)"
        [[ "${#to_disable[@]}" -gt 0 ]] && disable_json="$(printf '%s\n' "${to_disable[@]}" | jq -R . | jq -sc .)"
        jq -nc \
            --argjson missing "$missing_json" \
            --argjson toEnable "$enable_json" \
            --argjson toDisable "$disable_json" \
            '{declared: true, missing: $missing, toEnable: $toEnable, toDisable: $toDisable, applied: false}'
        return 0
    fi

    if [[ "$total" -eq 0 ]]; then
        [[ "$apply" -eq 0 && "$as_json" -eq 0 ]] && aphotic_ok "plugins already match aphotic.toml -- nothing to reconcile"
        return 0
    fi

    if [[ "$apply" -eq 0 ]]; then
        echo "Aphotic reconcile — dry run"
        echo
        local p
        for p in "${to_enable[@]}"; do printf '  enable   %s\n' "$p"; done
        for p in "${to_disable[@]}"; do printf '  disable  %s\n' "$p"; done
        for p in "${missing[@]}"; do printf '  (manual) aphotic plugin install %s\n' "$p"; done
        echo
        if [[ "$applicable" -gt 0 ]]; then
            printf '%s change(s) would be applied. Run with --apply to converge.\n' "$applicable"
        else
            echo "Nothing --apply can converge on its own -- install the missing plugin(s) above first."
        fi
        return 0
    fi

    # --apply from here down.
    if [[ "$applicable" -eq 0 ]]; then
        aphotic_log "nothing to enable or disable -- ${#missing[@]} plugin(s) still need 'aphotic plugin install' by hand"
        return 0
    fi

    source "${COMMANDS_DIR}/cmd_backup.sh"
    # >/dev/null, not captured: _aphotic_backup_create's own aphotic_ok
    # call writes to the same stdout as its final `echo "$id"`, so
    # capturing it here would fold that status line into the id itself.
    # Same reason cmd_restore.sh's --overwrite path discards it too.
    # aphotic_rollback finds the snapshot by label, not by id, so nothing
    # downstream needs the id anyway.
    _aphotic_backup_create --label "pre-reconcile" >/dev/null
    aphotic_log "pre-reconcile snapshot saved (aphotic rollback undoes this)"

    local failures=0 p
    for p in "${to_enable[@]}"; do
        aphotic_plugin_set_enabled "$p" true && aphotic_ok "enabled ${p}" || failures=$((failures + 1))
    done
    for p in "${to_disable[@]}"; do
        aphotic_plugin_set_enabled "$p" false && aphotic_ok "disabled ${p}" || failures=$((failures + 1))
    done

    if [[ "$failures" -eq 0 ]]; then
        aphotic_ok "reconcile complete -- ${applicable} change(s) applied"
    else
        aphotic_warn "reconcile finished with ${failures} failure(s) above -- 'aphotic rollback' restores ${snapshot} if needed"
    fi
    [[ "${#missing[@]}" -gt 0 ]] && aphotic_log "${#missing[@]} plugin(s) still need 'aphotic plugin install' by hand"
}
