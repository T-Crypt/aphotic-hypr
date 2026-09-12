#!/usr/bin/env bash
# aphotic status — one-screen snapshot of what Aphotic is actually
# running, versus `aphotic doctor` (dependency/path/coherence checks) and
# `aphotic diff` (the full drift report). Reads lib/aphotic/state.sh's
# shared helpers rather than re-deriving any of this.
# @cmd: status
# @cmd.desc: One-screen snapshot of profile, layers, plugins, services and version drift
# @cmd.group: CORE
# @cmd.opt: --json | Machine-readable snapshot

_aphotic_status_plugin_counts() {
    local ok=0 missing=0 extra=0 disabled=0 state name
    while IFS=$'\t' read -r name state; do
        [[ -z "$name" ]] && continue
        case "$state" in
            ok) ok=$((ok + 1)) ;;
            missing) missing=$((missing + 1)) ;;
            extra) extra=$((extra + 1)) ;;
            disabled) disabled=$((disabled + 1)) ;;
        esac
    done < <(_aphotic_state_plugin_drift)
    printf '%s\t%s\t%s\t%s\n' "$ok" "$missing" "$extra" "$disabled"
}

aphotic_cmd_status() {
    source "${LIB_DIR}/state.sh"

    local as_json=0
    for arg in "$@"; do
        case "$arg" in
            --json) as_json=1 ;;
            -h|--help)
                cat <<'HELP'
Usage: aphotic status [--json]

One-screen snapshot: version/checkout drift, install profile and layers,
plugin state versus aphotic.toml's declared [plugins] (if any), and the
same daemon/display-manager checks `aphotic doctor` runs. Read-only --
see `aphotic diff` for the full drift report and `aphotic reconcile` to
act on it.
HELP
                return 0
                ;;
        esac
    done

    local toml="${APHOTIC_DOTS_DIR}/aphotic.toml"
    local profile layers
    # aphotic_toml_get/_get_array return 1 when aphotic.toml itself is
    # missing (a bare checkout with no install.sh run yet) -- || true
    # keeps that a graceful "unknown" below rather than an abort under
    # set -e.
    profile="$(aphotic_toml_get "$toml" install profile)" || true
    layers="$(aphotic_toml_get_array "$toml" install layers | paste -sd, -)" || true

    local drift_status drift_branch drift_head drift_behind
    IFS=$'\t' read -r drift_status drift_branch drift_head drift_behind < <(_aphotic_state_version_drift)

    local declared="false" ok=0 missing=0 extra=0 disabled=0
    if _aphotic_state_plugins_declared; then
        declared="true"
        IFS=$'\t' read -r ok missing extra disabled < <(_aphotic_status_plugin_counts)
    fi

    local services daemon_state dm_state
    services="$(_aphotic_state_service_drift)"
    IFS=$'\t' read -r _ daemon_state _ <<<"$(grep '^daemon' <<<"$services")"
    IFS=$'\t' read -r _ dm_state _ <<<"$(grep '^displaymanager' <<<"$services")"

    local passthrough
    passthrough="$(_aphotic_state_passthrough --json)"
    if [[ "$as_json" -eq 1 ]]; then
        jq -nc \
            --argjson passthrough "$passthrough" \
            --arg version "$APHOTIC_VERSION" \
            --arg profile "${profile:-}" \
            --arg layers "${layers:-}" \
            --arg driftStatus "$drift_status" \
            --arg driftBranch "${drift_branch:-}" \
            --arg driftHead "${drift_head:-}" \
            --argjson driftBehind "${drift_behind:-0}" \
            --argjson pluginsDeclared "$declared" \
            --argjson pluginsOk "$ok" \
            --argjson pluginsMissing "$missing" \
            --argjson pluginsExtra "$extra" \
            --argjson pluginsDisabled "$disabled" \
            --arg daemon "$daemon_state" \
            --arg displayManager "$dm_state" \
            '{passthrough: $passthrough, version: $version, profile: $profile, layers: ($layers | split(",") | map(select(length > 0))),
              versionDrift: {status: $driftStatus, branch: $driftBranch, head: $driftHead, commitsBehind: $driftBehind},
              plugins: {declared: $pluginsDeclared, ok: $pluginsOk, missing: $pluginsMissing, extra: $pluginsExtra, disabled: $pluginsDisabled},
              services: {daemon: $daemon, displayManager: $displayManager}}'
        return 0
    fi

    echo "Aphotic status — aphotic ${APHOTIC_VERSION}"
    echo
    printf 'Profile: %s\n' "${profile:-unknown}"
    printf 'Layers:  %s\n' "${layers:-none}"
    echo
    case "$drift_status" in
        notgit) echo "Checkout: not a git checkout" ;;
        *)
            printf 'Checkout: %s @ %s\n' "$drift_branch" "$drift_head"
            case "$drift_status" in
                behind) printf '          %s commit(s) behind origin/main\n' "$drift_behind" ;;
                ok) echo "          up to date with origin/main" ;;
                not-main) echo "          not on main, drift not tracked" ;;
                no-origin-ref) echo "          no origin/main ref cached, run git fetch" ;;
            esac
            ;;
    esac
    echo
    if [[ "$declared" == "true" ]]; then
        printf 'Plugins:  %s ok, %s missing, %s extra, %s disabled (vs aphotic.toml)\n' "$ok" "$missing" "$extra" "$disabled"
    else
        echo "Plugins:  not declared in aphotic.toml, drift not tracked"
    fi
    printf 'Passthrough: %s\n' "$(jq -r '.status' <<<"$passthrough")"
    printf 'Daemon:   %s\n' "$daemon_state"
    printf 'Display manager: %s\n' "$dm_state"
}
