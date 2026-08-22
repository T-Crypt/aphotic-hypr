#!/usr/bin/env bash
# aphotic restore — deploy Aphotic's own default dotfiles into place.
# @cmd: restore
# @cmd.desc: Deploy upstream Aphotic dotfiles (populate/overwrite semantics)
# @cmd.group: LIFECYCLE
# @cmd.opt: --populate  | Only write files that don't already exist (safe, default)
# @cmd.opt: --overwrite | Back up current files then overwrite with defaults
#
# Manifest-driven like HyDE's restore_cfg.psv, simplified to two columns:
#   <path-relative-to-dots-repo>|<absolute-target-path>
# Blank lines and lines starting with # are ignored.
# Manifest lives at lib/aphotic/restore.manifest.

_aphotic_restore_manifest() {
    echo "${LIB_DIR}/restore.manifest"
}

aphotic_cmd_restore() {
    local mode="populate"
    for arg in "$@"; do
        case "$arg" in
            --populate) mode="populate" ;;
            --overwrite) mode="overwrite" ;;
            -h|--help)
                cat <<EOF
Usage: aphotic restore [--populate|--overwrite]

  --populate    Only deploy files that don't already exist at their
                target (default, non-destructive, safe for first install)
  --overwrite   Snapshot current files to a backup, then replace with
                Aphotic's upstream defaults (explicit, opt-in, destructive)

Reads ${LIB_DIR}/restore.manifest — one "src|dest" pair per line, src is
relative to APHOTIC_DOTS_DIR.
EOF
                return 0
                ;;
        esac
    done

    local manifest
    manifest="$(_aphotic_restore_manifest)"
    if [[ ! -r "$manifest" ]]; then
        aphotic_err "no restore manifest at ${manifest}"
        return 1
    fi

    if [[ ! -d "$APHOTIC_DOTS_DIR" ]]; then
        aphotic_err "APHOTIC_DOTS_DIR (${APHOTIC_DOTS_DIR}) does not exist — clone the dots repo first"
        return 1
    fi

    if [[ "$mode" == "overwrite" ]]; then
        aphotic_confirm "This backs up then overwrites existing configs with Aphotic defaults. Continue?" || {
            aphotic_log "aborted"; return 1
        }
        # reuse the backup command as a library function for the safety snapshot
        source "${COMMANDS_DIR}/cmd_backup.sh"
        _aphotic_backup_create --label "pre-restore" >/dev/null
    fi

    local deployed=0 skipped=0
    while IFS='|' read -r src dest; do
        [[ -z "$src" || "$src" == \#* ]] && continue
        local abs_src="${APHOTIC_DOTS_DIR}/${src}"
        local abs_dest="${dest/#\~/$HOME}"

        if [[ ! -e "$abs_src" ]]; then
            aphotic_warn "manifest source missing, skipping: ${src}"
            continue
        fi

        if [[ "$mode" == "populate" && -e "$abs_dest" ]]; then
            skipped=$((skipped + 1))
            continue
        fi

        mkdir -p "$(dirname "$abs_dest")"
        cp -a "$abs_src" "$abs_dest"
        deployed=$((deployed + 1))
    done < "$manifest"

    aphotic_ok "restore (${mode}) complete — ${deployed} deployed, ${skipped} already present"
    [[ "$deployed" -gt 0 ]] && aphotic_log "run 'aphotic reload --full' to apply"
}
