#!/usr/bin/env bash
# noctis update — pull the dots repo, re-run restore, reload.
# @cmd: update
# @cmd.desc: Update the dots repo and re-deploy config
# @cmd.opt: --dots-only | Only git-pull, skip restore + reload

noctis_cmd_update() {
    local dots_only=0
    for arg in "$@"; do
        [[ "$arg" == "--dots-only" ]] && dots_only=1
        [[ "$arg" == "-h" || "$arg" == "--help" ]] && {
            cat <<HELP
Usage: noctis update [--dots-only]

  --dots-only   Only git-pull NOCTIS_DOTS_DIR, skip restore + reload
HELP
            return 0
        }
    done

    if [[ ! -d "${NOCTIS_DOTS_DIR}/.git" ]]; then
        noctis_err "${NOCTIS_DOTS_DIR} is not a git repo"
        return 1
    fi

    noctis_log "pulling ${NOCTIS_DOTS_DIR}..."
    git -C "$NOCTIS_DOTS_DIR" pull --ff-only

    if [[ "$dots_only" -eq 1 ]]; then
        noctis_ok "dots updated (--dots-only, skipping restore/reload)"
        return 0
    fi

    source "${COMMANDS_DIR}/cmd_restore.sh"
    noctis_cmd_restore --populate

    source "${COMMANDS_DIR}/cmd_reload.sh"
    noctis_cmd_reload --full

    noctis_ok "update complete"
}
