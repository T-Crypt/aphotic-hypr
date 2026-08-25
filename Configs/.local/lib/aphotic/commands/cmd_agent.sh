#!/usr/bin/env bash
# aphotic agent — AI coding-agent usage tracking for the bar's agent popout.
# @cmd: agent
# @cmd.desc: Update the local agent usage record
# @cmd.group: CORE
# @cmd.opt: usage-update  | Parse local Claude/Codex transcripts and write agent-usage.json

APHOTIC_AGENT_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/.."

aphotic_cmd_agent() {
    case "${1:-}" in
        -h|--help|"")
            cat <<HELP
Usage: aphotic agent usage-update

  usage-update   Parse local Claude/Codex transcripts and write
                 \$APHOTIC_STATE_HOME/agent-usage.json (aggregate token
                 counts only -- never prompts, responses, or credentials)
HELP
            ;;
        usage-update)
            aphotic_require python3 || return 1
            python3 "${APHOTIC_AGENT_LIB_DIR}/agent_usage.py" "$APHOTIC_STATE_HOME"
            ;;
        *)
            aphotic_log "unknown agent subcommand: $1" >&2
            return 1
            ;;
    esac
}
