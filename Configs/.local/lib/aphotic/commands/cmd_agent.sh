#!/usr/bin/env bash
# aphotic agent -- AI coding-agent usage tracking for the bar's agent popout.
# @cmd: agent
# @cmd.desc: Track AI coding-agent usage and feed the agent event stream
# @cmd.group: CORE
# @cmd.opt: usage-update  | Parse local Claude/Codex transcripts and write agent-usage.json
# @cmd.opt: emit <event>  | Write one validated v2 agent event through the hook writer
# @cmd.opt: run --harness NAME -- <command...>  | Wrap a command with session_start and session_end

APHOTIC_AGENT_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/.."

aphotic_agent_emit() {
    python3 "${APHOTIC_AGENT_LIB_DIR}/agent_emit.py" "$@"
}

# Frames an arbitrary command as one harness session: session_start and an
# active turn before it, session_end after it, so a harness without a hook
# system shows open, active and ended on its own. A wrapper killed while the
# command still runs never writes the end; the writer's stale sweep reclaims
# the session file after 12 hours.
aphotic_agent_run() {
    local harness=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --harness)
                if [[ $# -lt 2 ]]; then
                    aphotic_log "agent run: --harness needs a value" >&2
                    return 2
                fi
                harness="$2"
                shift 2
                ;;
            --harness=*)
                harness="${1#--harness=}"
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                aphotic_log "agent run: unexpected argument '$1' (usage: aphotic agent run --harness NAME -- <command...>)" >&2
                return 2
                ;;
        esac
    done

    if [[ -z "$harness" ]]; then
        aphotic_log "agent run: --harness NAME is required" >&2
        return 2
    fi
    if [[ $# -eq 0 ]]; then
        aphotic_log "agent run: no command after --" >&2
        return 2
    fi

    local session="run-$(date +%s)-$$"
    local cwd="$PWD"

    aphotic_agent_emit session_start --session "$session" --harness "$harness" --cwd "$cwd"
    aphotic_agent_emit turn --session "$session" --harness "$harness"
    "$@"
    local rc=$?
    aphotic_agent_emit session_end --session "$session" --harness "$harness" --end-reason "exited"
    return "$rc"
}

aphotic_cmd_agent() {
    case "${1:-}" in
        -h|--help|"")
            cat <<HELP
Usage: aphotic agent usage-update
       aphotic agent emit <event> --session ID --harness NAME
               [--model M] [--provider P] [--cwd DIR] [--status S] [--end-reason R]
               [--tokens-in N] [--tokens-out N] [--cache-read N] [--cache-write N]
               [--reasoning-tokens N]
       aphotic agent run --harness NAME -- <command...>

  usage-update   Parse local Claude/Codex transcripts and write
                 \$APHOTIC_STATE_HOME/agent-usage.json (aggregate token
                 counts only -- never prompts, responses, or credentials)

  emit <event>   Write one validated v2 agent event through the hook
                 writer. For harnesses without a hook system of their
                 own: the event appears in the agent stream, tile and
                 graph like a native hook's. <event> is session_start,
                 session_end, turn, tool_call, usage, quota or error.

  run            Wrap any command: emits session_start and an active
                 turn before it and session_end after it, so the
                 command's session shows open, active and ended on its
                 own. Its exit code is returned unchanged.
HELP
            ;;
        usage-update)
            aphotic_require python3 || return 1
            python3 "${APHOTIC_AGENT_LIB_DIR}/agent_usage.py" "$APHOTIC_STATE_HOME"
            ;;
        emit)
            shift
            aphotic_require python3 || return 1
            aphotic_agent_emit "$@"
            ;;
        run)
            shift
            aphotic_require python3 || return 1
            aphotic_agent_run "$@"
            ;;
        *)
            aphotic_log "unknown agent subcommand: $1" >&2
            return 1
            ;;
    esac
}
