#!/usr/bin/env bash
# noctis backup — snapshot lifecycle for the dotfiles noctis manages.
# @cmd: backup
# @cmd.desc: Snapshot, list, revert, or prune dotfile backups
# @cmd.group: LIFECYCLE
# @cmd.opt: create [--label <name>] | Snapshot current dotfiles state
# @cmd.opt: list                     | List available snapshots
# @cmd.opt: revert <id>              | Restore a specific snapshot
# @cmd.opt: clean [--keep N]         | Prune old snapshots (default keep 10)
#
# Distinct from `noctis restore`: backup/revert deals in explicit,
# timestamped snapshots you created yourself (HyDE's "backup all / revert"
# concept). `restore` deploys Noctis's own upstream defaults with
# populate/overwrite semantics (HyDE's P/O flags).

_noctis_backup_targets=(
    "$HOME/.config/hypr"
    "$QUICKSHELL_CONFIG_DIR"
    "$NOCTIS_CONFIG_HOME"
)

_noctis_backup_create() {
    local label="manual"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --label) label="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local id dest missing=0
    id="$(date +%Y%m%d-%H%M%S)-${label}"
    dest="${NOCTIS_BACKUP_DIR}/${id}"
    mkdir -p "$dest"

    for target in "${_noctis_backup_targets[@]}"; do
        if [[ -e "$target" ]]; then
            cp -a "$target" "${dest}/$(basename "$target")"
        else
            missing=$((missing + 1))
        fi
    done

    printf '%s\n' "$label" > "${dest}/.label"
    date -Iseconds > "${dest}/.created"

    noctis_ok "backup created: ${id}"
    [[ "$missing" -gt 0 ]] && noctis_warn "${missing} target(s) did not exist and were skipped"
    echo "$id"
}

_noctis_backup_list() {
    if [[ ! -d "$NOCTIS_BACKUP_DIR" ]] || [[ -z "$(ls -A "$NOCTIS_BACKUP_DIR" 2>/dev/null)" ]]; then
        noctis_log "no backups yet — run 'noctis backup create' first"
        return 0
    fi
    printf '  %-28s %-14s %s\n' "ID" "LABEL" "CREATED"
    for dir in "$NOCTIS_BACKUP_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local id label created
        id="$(basename "$dir")"
        label="$(cat "${dir}.label" 2>/dev/null || echo unlabeled)"
        created="$(cat "${dir}.created" 2>/dev/null || echo unknown)"
        printf '  %-28s %-14s %s\n' "$id" "$label" "$created"
    done
}

_noctis_backup_revert() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        noctis_err "usage: noctis backup revert <id>"
        return 1
    fi
    local src="${NOCTIS_BACKUP_DIR}/${id}"
    if [[ ! -d "$src" ]]; then
        noctis_err "no such backup: ${id} (see 'noctis backup list')"
        return 1
    fi

    noctis_confirm "This overwrites your current config with backup '${id}'. Continue?" || {
        noctis_log "aborted"
        return 1
    }

    # Safety net: snapshot current state before reverting, so a revert
    # is itself always reversible.
    _noctis_backup_create --label "pre-revert" >/dev/null

    for target in "${_noctis_backup_targets[@]}"; do
        local rel="${src}/$(basename "$target")"
        if [[ -e "$rel" ]]; then
            rm -rf "$target"
            cp -a "$rel" "$target"
        fi
    done

    noctis_ok "reverted to backup ${id}"
    noctis_log "run 'noctis reload --full' to apply"
}

_noctis_backup_clean() {
    local keep=10
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --keep) keep="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -d "$NOCTIS_BACKUP_DIR" ]] || return 0
    local total
    total=$(find "$NOCTIS_BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d | wc -l)
    if [[ "$total" -le "$keep" ]]; then
        noctis_log "nothing to clean (${total} backups, keeping ${keep})"
        return 0
    fi

    local to_remove=$((total - keep))
    find "$NOCTIS_BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d -printf '%T@ %p\n' \
        | sort -n | head -n "$to_remove" | cut -d' ' -f2- \
        | while read -r dir; do
            noctis_log "removing $(basename "$dir")"
            rm -rf "$dir"
        done
    noctis_ok "cleaned ${to_remove} old backup(s), kept ${keep}"
}

noctis_cmd_backup() {
    local sub="${1:-}"
    shift || true
    case "$sub" in
        create) _noctis_backup_create "$@" ;;
        list)   _noctis_backup_list "$@" ;;
        revert) _noctis_backup_revert "$@" ;;
        clean)  _noctis_backup_clean "$@" ;;
        ""|-h|--help)
            cat <<EOF
Usage: noctis backup <create|list|revert|clean> [args]

  create [--label <name>]   Snapshot current dotfiles state
  list                      List available snapshots
  revert <id>               Restore a snapshot (auto-snapshots current state first)
  clean [--keep N]          Prune old snapshots, default keep 10
EOF
            ;;
        *)
            noctis_err "unknown backup subcommand: ${sub}"
            return 1
            ;;
    esac
}
