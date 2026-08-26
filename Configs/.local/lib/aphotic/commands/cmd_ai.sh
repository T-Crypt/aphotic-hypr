#!/usr/bin/env bash
# aphotic ai — status and profile switching for the Claude Code / Ollama panel.
# @cmd: ai
# @cmd.desc: Check AI backend status, switch the active provider profile
# @cmd.group: AI
# @cmd.opt: status         | Show reachability of Claude Code / Ollama, loaded models
# @cmd.opt: profile <name> | Switch the shell's AI-panel provider/model config
# @cmd.opt: fit [n]        | Hardware-aware model recommendations via llmfit (default top 3)

aphotic_cmd_ai() {
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
                if ollama list >/tmp/aphotic-ollama-list 2>/dev/null; then
                    printf '  [ok]   ollama reachable, models:\n'
                    tail -n +2 /tmp/aphotic-ollama-list | sed 's/^/    /'
                else
                    printf '  [warn] ollama installed but not responding (is the service running?)\n'
                fi
            else
                printf '  [MISS] ollama not found on PATH\n'
            fi
            rm -f /tmp/aphotic-ollama-list
            ;;
        profile)
            local name="${1:-}"
            [[ -z "$name" ]] && { aphotic_err "usage: aphotic ai profile <name>"; return 1; }
            aphotic_json_set "ai.activeProfile" "$name"
            aphotic_ok "AI panel profile set to '${name}'"
            aphotic_log "define profiles under ${APHOTIC_CONFIG_HOME}/ai-profiles/ (TODO)"
            ;;
        fit)
            aphotic_require jq || return 1
            if ! command -v llmfit >/dev/null 2>&1; then
                aphotic_err "llmfit not found on PATH"
                aphotic_log "install it via the 'ai' profile layer (./install.sh --with ai), or manually: curl -fsSL https://llmfit.axjns.dev/install.sh | sh"
                return 1
            fi

            local limit="${1:-3}" out err rc=0
            out="$(mktemp)"; err="$(mktemp)"
            llmfit recommend --json --limit "$limit" >"$out" 2>"$err" || rc=$?

            if [[ -s "$err" ]]; then
                aphotic_warn "llmfit reported:"
                sed 's/^/  /' "$err" >&2
            fi

            if [[ "$rc" -ne 0 ]] || ! jq empty "$out" >/dev/null 2>&1; then
                aphotic_err "llmfit failed to detect hardware or produce valid JSON (exit ${rc})"
                rm -f "$out" "$err"
                return 1
            fi

            echo "Hardware detected:"
            jq -r '.system |
                "  CPU:  \(.cpu_name) (\(.cpu_cores) cores)",
                "  RAM:  \(.available_ram_gb) / \(.total_ram_gb) GB available",
                (if .has_gpu then "  GPU:  \(.gpu_name) (\(.gpu_vram_gb) GB, \(.backend))" else "  GPU:  none detected" end)
            ' "$out"
            echo
            echo "Top recommendations:"
            if [[ "$(jq '.models | length' "$out")" -eq 0 ]]; then
                echo "  (no models meet the minimum fit threshold on this hardware)"
            else
                jq -r '.models | to_entries[] |
                    "  \(.key + 1). \(.value.name) (\(.value.provider)) -- \(.value.fit_level) fit, \(.value.best_quant), ~\(.value.estimated_tps) tok/s",
                    "     \(.value.parameter_count) params, \(.value.context_length) ctx, score \(.value.score)/100"
                ' "$out"
            fi

            rm -f "$out" "$err"
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: aphotic ai <status|profile|fit> [args]

  status          Show Claude Code / Ollama reachability and loaded models
  profile <name>  Switch the AI-panel's active provider/model profile
  fit [n]         Hardware-aware model recommendations via llmfit (default top 3)
HELP
            ;;
        *)
            aphotic_err "unknown ai subcommand: ${sub}"
            return 1
            ;;
    esac
}
