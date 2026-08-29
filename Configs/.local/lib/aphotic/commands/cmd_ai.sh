#!/usr/bin/env bash
# aphotic ai — status and profile switching for the Claude Code / Ollama panel.
# @cmd: ai
# @cmd.desc: Check AI backend status, switch the active provider profile
# @cmd.group: AI
# @cmd.opt: status         | Show reachability of Claude Code / Ollama, loaded models
# @cmd.opt: profile <provider>[:<model>] | Switch the AI panel's active provider (ollama/claude/codex/gemini/chatgpt), optionally the ollama model
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
            # Real bug this replaces: this used to write "ai.activeProfile"
            # into shell.json (via aphotic_json_set, which always targets
            # $APHOTIC_CONFIG_FILE) -- but the AI Chat panel's own config
            # (activeProvider/ollamaModel/...) lives in a completely
            # separate file, services/ai/AiConfig.qml's
            # ~/.config/aphotic/ai-config.json, which nothing ever reads
            # shell.json's "ai" key from. The old command genuinely could
            # not have changed anything the panel showed, ever, and the
            # "define profiles under .../ai-profiles/ (TODO)" log line
            # promised a directory-of-named-presets system that was never
            # built. Rebuilt as a real, working shortcut: <provider> or
            # <provider>:<model> (model only meaningful for ollama, quietly
            # ignored otherwise), writing directly to AiConfig's own
            # ai-config.json in its own schema -- AiConfig's FileView
            # already watches this path (same pattern Themes.qml/theme.json
            # use), so a running shell picks this up live, no reload needed.
            aphotic_require jq || return 1
            local arg="${1:-}" provider model
            [[ -z "$arg" ]] && { aphotic_err "usage: aphotic ai profile <provider>[:<model>] (provider: ollama, claude, codex, gemini, chatgpt)"; return 1; }
            provider="${arg%%:*}"
            model=""
            [[ "$arg" == *:* ]] && model="${arg#*:}"

            case "$provider" in
                ollama|claude|codex|gemini|chatgpt) ;;
                *)
                    aphotic_err "unknown provider '${provider}' -- must be one of: ollama, claude, codex, gemini, chatgpt"
                    return 1
                    ;;
            esac

            local conf="${APHOTIC_CONFIG_HOME}/ai-config.json" tmp
            mkdir -p "$APHOTIC_CONFIG_HOME"
            [[ -f "$conf" ]] || echo '{}' > "$conf"
            tmp="$(mktemp)"
            if [[ -n "$model" && "$provider" == "ollama" ]]; then
                jq --arg p "$provider" --arg m "$model" '.activeProvider = $p | .ollamaModel = $m' "$conf" > "$tmp"
            else
                jq --arg p "$provider" '.activeProvider = $p' "$conf" > "$tmp"
            fi
            mv "$tmp" "$conf"

            if [[ -n "$model" && "$provider" != "ollama" ]]; then
                aphotic_warn "':${model}' is ignored -- only the ollama profile has a model to set"
            fi
            aphotic_ok "AI panel profile set to '${provider}'$([ -n "$model" ] && [ "$provider" == "ollama" ] && echo " (model: ${model})")"
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

  status                     Show Claude Code / Ollama reachability and loaded models
  profile <provider>[:<model>]
                             Switch the AI panel's active provider
                             (ollama, claude, codex, gemini, chatgpt) --
                             optionally set the model too (ollama only,
                             e.g. 'ollama:llama3.1:8b')
  fit [n]                    Hardware-aware model recommendations via llmfit (default top 3)
HELP
            ;;
        *)
            aphotic_err "unknown ai subcommand: ${sub}"
            return 1
            ;;
    esac
}
