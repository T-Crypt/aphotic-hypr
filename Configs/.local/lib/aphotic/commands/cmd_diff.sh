#!/usr/bin/env bash
# aphotic diff — full drift report: what aphotic.toml (and the profile's
# own package lists) declare versus what's actually true on this
# machine. Read-only, same boundary `aphotic sync --check` already
# respects: nothing here is applied. `aphotic reconcile` acts on this.
# @cmd: diff
# @cmd.desc: Report drift between aphotic.toml and what's actually installed/running
# @cmd.group: CORE
# @cmd.opt: --json | Machine-readable drift report

# One line per row, prefixed with the mark that also decides whether it
# counts toward "N changes required": ok never counts, warn and missing
# always do, skip never does (nothing to reconcile, just not tracked).
_aphotic_diff_line() {
    local mark="$1" label="$2" detail="$3"
    case "$mark" in
        ok)   printf '\xe2\x9c\x93 %-10s %s\n' "$label" "$detail" ;;
        warn) printf '! %-10s %s\n' "$label" "$detail" ;;
        miss) printf -- '- %-10s %s\n' "$label" "$detail" ;;
        skip) printf '  %-10s %s\n' "$label" "$detail" ;;
    esac
}

aphotic_cmd_diff() {
    source "${LIB_DIR}/state.sh"
    source "${COMMANDS_DIR}/cmd_sync.sh"

    local as_json=0
    for arg in "$@"; do
        case "$arg" in
            --json) as_json=1 ;;
            -h|--help)
                cat <<'HELP'
Usage: aphotic diff [--json]

Full drift report: packages the current profile/layers ask for but
aren't installed, plugins declared in aphotic.toml's [plugins] section
that aren't installed/enabled (or the reverse), and the daemon/display-
manager checks `aphotic doctor` also runs. Read-only. `aphotic reconcile`
converges what it safely can.
HELP
                return 0
                ;;
        esac
    done

    local missing_packages
    missing_packages="$(_aphotic_sync_missing_packages "$APHOTIC_DOTS_DIR")"
    local missing_count=0
    [[ -n "$missing_packages" ]] && missing_count="$(wc -l <<<"$missing_packages")"

    local plugins_declared="false" plugin_missing=() plugin_extra=() plugin_disabled=() plugin_ok=0
    if _aphotic_state_plugins_declared; then
        plugins_declared="true"
        local name state
        while IFS=$'\t' read -r name state; do
            [[ -z "$name" ]] && continue
            case "$state" in
                missing) plugin_missing+=("$name") ;;
                extra) plugin_extra+=("$name") ;;
                disabled) plugin_disabled+=("$name") ;;
                ok) plugin_ok=$((plugin_ok + 1)) ;;
            esac
        done < <(_aphotic_state_plugin_drift)
    fi

    local services daemon_state dm_state dm_detail
    services="$(_aphotic_state_service_drift)"
    IFS=$'\t' read -r _ daemon_state _ <<<"$(grep '^daemon' <<<"$services")"
    IFS=$'\t' read -r _ dm_state dm_detail <<<"$(grep '^displaymanager' <<<"$services")"

    local drift_status drift_branch drift_head drift_behind
    IFS=$'\t' read -r drift_status drift_branch drift_head drift_behind < <(_aphotic_state_version_drift)

    local changes=0
    [[ "$missing_count" -gt 0 ]] && changes=$((changes + missing_count))
    changes=$((changes + ${#plugin_missing[@]} + ${#plugin_extra[@]} + ${#plugin_disabled[@]}))
    [[ "$daemon_state" != "running" ]] && changes=$((changes + 1))
    [[ "$dm_state" == "conflict" ]] && changes=$((changes + 1))
    [[ "$drift_status" == "behind" ]] && changes=$((changes + 1))

    local passthrough
    passthrough="$(_aphotic_state_passthrough --json)"
    local passthrough_changes
    passthrough_changes="$(jq '[.checks[] | select(.status != "ok")] | length' <<<"$passthrough")"
    [[ "$(jq -r '.status' <<<"$passthrough")" != INVALID ]] || passthrough_changes=1
    changes=$((changes + passthrough_changes))
    if [[ "$as_json" -eq 1 ]]; then
        local missing_json="[]" plugin_missing_json="[]" plugin_extra_json="[]" plugin_disabled_json="[]"
        [[ -n "$missing_packages" ]] && missing_json="$(printf '%s\n' "$missing_packages" | jq -R . | jq -sc .)"
        [[ "${#plugin_missing[@]}" -gt 0 ]] && plugin_missing_json="$(printf '%s\n' "${plugin_missing[@]}" | jq -R . | jq -sc .)"
        [[ "${#plugin_extra[@]}" -gt 0 ]] && plugin_extra_json="$(printf '%s\n' "${plugin_extra[@]}" | jq -R . | jq -sc .)"
        [[ "${#plugin_disabled[@]}" -gt 0 ]] && plugin_disabled_json="$(printf '%s\n' "${plugin_disabled[@]}" | jq -R . | jq -sc .)"

        jq -nc \
            --argjson passthrough "$passthrough" \
            --argjson missingPackages "$missing_json" \
            --argjson pluginsDeclared "$plugins_declared" \
            --argjson pluginsOk "$plugin_ok" \
            --argjson pluginsMissing "$plugin_missing_json" \
            --argjson pluginsExtra "$plugin_extra_json" \
            --argjson pluginsDisabled "$plugin_disabled_json" \
            --arg daemon "$daemon_state" \
            --arg displayManager "$dm_state" \
            --arg displayManagerDetail "${dm_detail:-}" \
            --arg versionStatus "$drift_status" \
            --argjson versionCommitsBehind "${drift_behind:-0}" \
            --argjson changesRequired "$changes" \
            '{passthrough: $passthrough, missingPackages: $missingPackages,
              plugins: {declared: $pluginsDeclared, ok: $pluginsOk, missing: $pluginsMissing, extra: $pluginsExtra, disabled: $pluginsDisabled},
              services: {daemon: $daemon, displayManager: $displayManager, displayManagerDetail: $displayManagerDetail},
              version: {status: $versionStatus, commitsBehind: $versionCommitsBehind},
              changesRequired: $changesRequired}'
        return 0
    fi

    echo "Aphotic system drift"
    printf 'Passthrough: %s\n' "$(jq -r '.status' <<<"$passthrough")"
    jq -r '.checks[] | "  [\(.status)] \(.key): desired \(.desired), actual \(.actual)"' <<<"$passthrough"
    echo

    if [[ "$missing_count" -eq 0 ]]; then
        _aphotic_diff_line ok packages "all present"
    else
        _aphotic_diff_line miss packages "${missing_count} missing: $(printf '%s' "$missing_packages" | tr '\n' ' ')"
    fi

    if [[ "$plugins_declared" == "false" ]]; then
        _aphotic_diff_line skip plugins "not declared in aphotic.toml, drift not tracked"
    elif [[ "${#plugin_missing[@]}" -eq 0 && "${#plugin_extra[@]}" -eq 0 && "${#plugin_disabled[@]}" -eq 0 ]]; then
        _aphotic_diff_line ok plugins "in sync (${plugin_ok})"
    else
        local p
        for p in "${plugin_missing[@]}"; do
            _aphotic_diff_line miss plugins "${p} missing"
        done
        for p in "${plugin_disabled[@]}"; do
            _aphotic_diff_line warn plugins "${p} installed but disabled"
        done
        for p in "${plugin_extra[@]}"; do
            _aphotic_diff_line warn plugins "${p} not desired (enabled, not declared)"
        done
    fi

    if [[ "$daemon_state" == "running" ]]; then
        _aphotic_diff_line ok services "daemon running"
    else
        _aphotic_diff_line miss services "daemon not running (aphotic shell -d)"
    fi
    if [[ "$dm_state" == "conflict" ]]; then
        _aphotic_diff_line warn services "$dm_detail"
    fi

    case "$drift_status" in
        notgit) _aphotic_diff_line skip version "not a git checkout" ;;
        not-main) _aphotic_diff_line skip version "not on main, drift not tracked" ;;
        no-origin-ref) _aphotic_diff_line skip version "no origin/main ref cached, run git fetch" ;;
        behind) _aphotic_diff_line warn version "${drift_behind} commit(s) behind origin/main" ;;
        ok) _aphotic_diff_line ok version "up to date with origin/main" ;;
    esac

    echo
    if [[ "$changes" -eq 0 ]]; then
        echo "no changes required"
    else
        printf '%s change(s) required\n' "$changes"
    fi
}
