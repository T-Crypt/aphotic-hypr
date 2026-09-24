#!/usr/bin/env bash
# aphotic update — follow the saved channel: stable moves to the newest
# release tag, edge pulls the current branch. Re-run restore, reload.
# @cmd: update
# @cmd.desc: Update the dots repo and re-deploy config
# @cmd.group: LIFECYCLE
# @cmd.opt: --dots-only | Only git-pull, skip restore + reload
# @cmd.opt: --channel <stable|edge> | Override the saved channel for this update

aphotic_cmd_update() {
    local dots_only=0 channel=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dots-only) dots_only=1; shift ;;
            --channel)
                [[ -n "${2:-}" ]] || { aphotic_err "update: missing value for --channel (stable|edge)"; return 1; }
                channel="$2"; shift 2
                ;;
            -h|--help)
                cat <<HELP
Usage: aphotic update [--dots-only] [--channel stable|edge]

  --dots-only           Only update APHOTIC_DOTS_DIR, skip restore + reload
  --channel <stable|edge>  Override the saved channel for this update.
                        stable moves to the newest release tag, edge
                        pulls the current branch. Default: saved channel
                        from ~/.local/state/aphotic/channel, else stable.
HELP
                return 0
                ;;
            *) aphotic_err "update: unknown flag '$1'"; return 1 ;;
        esac
    done

    if [[ ! -d "${APHOTIC_DOTS_DIR}/.git" ]]; then
        aphotic_err "${APHOTIC_DOTS_DIR} is not a git repo"
        return 1
    fi

    if [[ -z "$channel" ]]; then
        channel="stable"
        [[ -f "${APHOTIC_STATE_HOME}/channel" ]] && channel="$(<"${APHOTIC_STATE_HOME}/channel")"
    fi

    case "$channel" in
        edge)
            # A stable install leaves the checkout detached at a tag.
            if ! git -C "$APHOTIC_DOTS_DIR" symbolic-ref -q HEAD >/dev/null; then
                git -C "$APHOTIC_DOTS_DIR" checkout --quiet main || return 1
            fi
            aphotic_log "pulling ${APHOTIC_DOTS_DIR} (channel edge)..."
            git -C "$APHOTIC_DOTS_DIR" pull --ff-only
            ;;
        stable)
            aphotic_log "fetching tags in ${APHOTIC_DOTS_DIR} (channel stable)..."
            git -C "$APHOTIC_DOTS_DIR" fetch --tags --quiet
            local tag
            tag="$(git -C "$APHOTIC_DOTS_DIR" tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n1)"
            if [[ -z "$tag" ]]; then
                aphotic_warn "no release tags found; staying on the current commit"
            else
                aphotic_log "moving to ${tag}..."
                git -C "$APHOTIC_DOTS_DIR" checkout --quiet "$tag"
            fi
            ;;
        *)
            aphotic_err "update: invalid channel '$channel' (stable|edge)"
            return 1
            ;;
    esac

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
