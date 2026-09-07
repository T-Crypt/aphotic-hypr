#!/usr/bin/env bash
# aphotic rollback — undo the most recent `aphotic reconcile --apply`.
# Thin wrapper around `aphotic backup`'s existing revert: no new revert
# logic, just finds the latest snapshot reconcile labelled and calls it.
# @cmd: rollback
# @cmd.desc: Restore the most recent pre-reconcile snapshot
# @cmd.group: LIFECYCLE
# @cmd.opt: --yes | Skip the confirmation prompt

# Most recent backup directory whose .label matches, or nothing (exit 1)
# if there is none. Backup ids are timestamp-prefixed, but sorted by
# mtime here (same as _aphotic_backup_clean) rather than trusting the
# name to sort correctly forever.
_aphotic_rollback_latest_snapshot() {
    local label="$1" dir found=""
    [[ -d "$APHOTIC_BACKUP_DIR" ]] || return 1
    while IFS= read -r dir; do
        [[ -f "${dir}/.label" ]] || continue
        [[ "$(<"${dir}/.label")" == "$label" ]] || continue
        found="$(basename "$dir")"
    done < <(find "$APHOTIC_BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2-)
    [[ -n "$found" ]] || return 1
    printf '%s\n' "$found"
}

aphotic_cmd_rollback() {
    local assume_yes=0
    for arg in "$@"; do
        case "$arg" in
            -y|--yes) assume_yes=1 ;;
            -h|--help)
                cat <<'HELP'
Usage: aphotic rollback [--yes]

Restores the most recent pre-reconcile snapshot -- the one `aphotic
reconcile --apply` writes automatically before it changes anything.
Thin wrapper around `aphotic backup revert`; use `aphotic backup list`
and `aphotic backup revert <id>` directly to restore a different
snapshot.
HELP
                return 0
                ;;
        esac
    done

    source "${COMMANDS_DIR}/cmd_backup.sh"
    local id
    id="$(_aphotic_rollback_latest_snapshot pre-reconcile)" || {
        aphotic_err "no pre-reconcile snapshot found -- nothing for 'aphotic rollback' to undo (see 'aphotic backup list')"
        return 1
    }

    if [[ "$assume_yes" -eq 1 ]]; then
        _aphotic_backup_revert --yes "$id"
    else
        _aphotic_backup_revert "$id"
    fi
}
