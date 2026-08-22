#!/usr/bin/env bash
# aphotic backup — snapshot lifecycle for the dotfiles aphotic manages.
# @cmd: backup
# @cmd.desc: Snapshot, list, revert, or prune dotfile backups
# @cmd.group: LIFECYCLE
# @cmd.opt: create [--label <name>] | Snapshot current dotfiles state
# @cmd.opt: list                     | List available snapshots
# @cmd.opt: revert <id>              | Restore a specific snapshot
# @cmd.opt: clean [--keep N]         | Prune old snapshots (default keep 10)
#
# Distinct from `aphotic restore`: backup/revert deals in explicit,
# timestamped snapshots you created yourself (HyDE's "backup all / revert"
# concept). `restore` deploys Aphotic's own upstream defaults with
# populate/overwrite semantics (HyDE's P/O flags).

_aphotic_backup_targets=(
    "$HOME/.config/hypr"
    "$QUICKSHELL_CONFIG_DIR"
    "$APHOTIC_CONFIG_HOME"
)

_aphotic_backup_create() {
    local label="manual"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --label) label="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local id dest missing=0
    id="$(date +%Y%m%d-%H%M%S)-${label}"
    dest="${APHOTIC_BACKUP_DIR}/${id}"
    mkdir -p "$dest"

    for target in "${_aphotic_backup_targets[@]}"; do
        if [[ -e "$target" ]]; then
            cp -a "$target" "${dest}/$(basename "$target")"
        else
            missing=$((missing + 1))
        fi
    done

    printf '%s\n' "$label" > "${dest}/.label"
    date -Iseconds > "${dest}/.created"

    aphotic_ok "backup created: ${id}"
    [[ "$missing" -gt 0 ]] && aphotic_warn "${missing} target(s) did not exist and were skipped"
    echo "$id"
}

_aphotic_backup_list() {
    if [[ ! -d "$APHOTIC_BACKUP_DIR" ]] || [[ -z "$(ls -A "$APHOTIC_BACKUP_DIR" 2>/dev/null)" ]]; then
        aphotic_log "no backups yet — run 'aphotic backup create' first"
        return 0
    fi
    printf '  %-28s %-14s %s\n' "ID" "LABEL" "CREATED"
    for dir in "$APHOTIC_BACKUP_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local id label created
        id="$(basename "$dir")"
        label="$(cat "${dir}.label" 2>/dev/null || echo unlabeled)"
        created="$(cat "${dir}.created" 2>/dev/null || echo unknown)"
        printf '  %-28s %-14s %s\n' "$id" "$label" "$created"
    done
}

_aphotic_backup_revert() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        aphotic_err "usage: aphotic backup revert <id>"
        return 1
    fi
    local src="${APHOTIC_BACKUP_DIR}/${id}"
    if [[ ! -d "$src" ]]; then
        aphotic_err "no such backup: ${id} (see 'aphotic backup list')"
        return 1
    fi

    aphotic_confirm "This overwrites your current config with backup '${id}'. Continue?" || {
        aphotic_log "aborted"
        return 1
    }

    # Safety net: snapshot current state before reverting, so a revert
    # is itself always reversible.
    _aphotic_backup_create --label "pre-revert" >/dev/null

    for target in "${_aphotic_backup_targets[@]}"; do
        local rel="${src}/$(basename "$target")"
        if [[ -e "$rel" ]]; then
            rm -rf "$target"
            cp -a "$rel" "$target"
        fi
    done

    aphotic_ok "reverted to backup ${id}"
    aphotic_log "run 'aphotic reload --full' to apply"
}

_aphotic_backup_clean() {
    local keep=10
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --keep) keep="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -d "$APHOTIC_BACKUP_DIR" ]] || return 0
    local total
    total=$(find "$APHOTIC_BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d | wc -l)
    if [[ "$total" -le "$keep" ]]; then
        aphotic_log "nothing to clean (${total} backups, keeping ${keep})"
        return 0
    fi

    local to_remove=$((total - keep))
    find "$APHOTIC_BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d -printf '%T@ %p\n' \
        | sort -n | head -n "$to_remove" | cut -d' ' -f2- \
        | while read -r dir; do
            aphotic_log "removing $(basename "$dir")"
            rm -rf "$dir"
        done
    aphotic_ok "cleaned ${to_remove} old backup(s), kept ${keep}"
}

aphotic_cmd_backup() {
    local sub="${1:-}"
    shift || true
    case "$sub" in
        create) _aphotic_backup_create "$@" ;;
        list)   _aphotic_backup_list "$@" ;;
        revert) _aphotic_backup_revert "$@" ;;
        clean)  _aphotic_backup_clean "$@" ;;
        ""|-h|--help)
            cat <<EOF
Usage: aphotic backup <create|list|revert|clean> [args]

  create [--label <name>]   Snapshot current dotfiles state
  list                      List available snapshots
  revert <id>               Restore a snapshot (auto-snapshots current state first)
  clean [--keep N]          Prune old snapshots, default keep 10
EOF
            ;;
        *)
            aphotic_err "unknown backup subcommand: ${sub}"
            return 1
            ;;
    esac
}
