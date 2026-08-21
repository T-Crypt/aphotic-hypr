#!/usr/bin/env bash
# noctis ai — status and profile switching for the Claude Code / Ollama panel.
# @cmd: ai
# @cmd.desc: Check AI backend status, switch the active provider profile
# @cmd.group: AI
# @cmd.opt: status         | Show reachability of Claude Code / Ollama, loaded models
# @cmd.opt: profile <name> | Switch the shell's AI-panel provider/model config

noctis_cmd_ai() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        status)
            echo "Claude Code:"
            if command -v claude >/dev/null 2>&1; then
                printf '  [ok]   claude CLI on PATH (%s)\n' "$(command -v claude)"
            else
                printf '  [MISS] claude CLI not found on PATH\n'
            fi
            echo
            echo "Ollama:"
            if command -v ollama >/dev/null 2>&1; then
                if ollama list >/tmp/noctis-ollama-list 2>/dev/null; then
                    printf '  [ok]   ollama reachable, models:\n'
                    tail -n +2 /tmp/noctis-ollama-list | sed 's/^/    /'
                else
                    printf '  [warn] ollama installed but not responding (is the service running?)\n'
                fi
            else
                printf '  [MISS] ollama not found on PATH\n'
            fi
            rm -f /tmp/noctis-ollama-list
            ;;
        profile)
            local name="${1:-}"
            [[ -z "$name" ]] && { noctis_err "usage: noctis ai profile <name>"; return 1; }
            noctis_json_set "ai.activeProfile" "$name"
            noctis_ok "AI panel profile set to '${name}'"
            noctis_log "define profiles under ${NOCTIS_CONFIG_HOME}/ai-profiles/ (TODO)"
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: noctis ai <status|profile> [args]

  status          Show Claude Code / Ollama reachability and loaded models
  profile <name>  Switch the AI-panel's active provider/model profile
HELP
            ;;
        *)
            noctis_err "unknown ai subcommand: ${sub}"
            return 1
            ;;
    esac
}
