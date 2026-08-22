#!/usr/bin/env bash
# aphotic update — pull the dots repo, re-run restore, reload.
# @cmd: update
# @cmd.desc: Update the dots repo and re-deploy config
# @cmd.group: LIFECYCLE
# @cmd.opt: --dots-only | Only git-pull, skip restore + reload

aphotic_cmd_update() {
    local dots_only=0
    for arg in "$@"; do
        [[ "$arg" == "--dots-only" ]] && dots_only=1
        [[ "$arg" == "-h" || "$arg" == "--help" ]] && {
            cat <<HELP
Usage: aphotic update [--dots-only]

  --dots-only   Only git-pull APHOTIC_DOTS_DIR, skip restore + reload
HELP
            return 0
        }
    done

    if [[ ! -d "${APHOTIC_DOTS_DIR}/.git" ]]; then
        aphotic_err "${APHOTIC_DOTS_DIR} is not a git repo"
        return 1
    fi

    aphotic_log "pulling ${APHOTIC_DOTS_DIR}..."
    git -C "$APHOTIC_DOTS_DIR" pull --ff-only

    if [[ "$dots_only" -eq 1 ]]; then
        aphotic_ok "dots updated (--dots-only, skipping restore/reload)"
        return 0
    fi

    source "${COMMANDS_DIR}/cmd_restore.sh"
    aphotic_cmd_restore --populate

    source "${COMMANDS_DIR}/cmd_reload.sh"
    aphotic_cmd_reload --full

    aphotic_ok "update complete"
}
