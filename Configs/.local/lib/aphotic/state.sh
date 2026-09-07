#!/usr/bin/env bash
# lib/aphotic/state.sh — desired vs. actual plugin state.
#
# `aphotic.toml`'s optional `[plugins] enabled = [...]` is desired state;
# the plugin registry on disk (APHOTIC_PLUGINS_DIR + APHOTIC_PLUGINS_STATE_FILE,
# read through aphotic_plugin_names()/aphotic_plugin_is_enabled() in
# globalcontrol.sh) is actual state. Nothing here writes either side --
# it only reads both, so `aphotic diff`/`aphotic status`/`aphotic reconcile`
# share one comparison instead of each re-deriving it.
#
# Not a cmd_*.sh: this is a library sourced by other commands, same as
# globalcontrol.sh itself, and stays out of the dispatcher's command
# discovery by living directly in lib/aphotic/ rather than commands/.

# One desired plugin name per line, empty if the section is absent —
# absence means "nothing declared", not "nothing should be enabled", so
# callers must not treat an empty result as "disable everything".
_aphotic_state_desired_plugins() {
    aphotic_toml_get_array "${APHOTIC_DOTS_DIR}/aphotic.toml" plugins enabled
}

# One installed-and-enabled plugin name per line.
_aphotic_state_actual_plugins() {
    local name
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        aphotic_plugin_is_enabled "$name" && printf '%s\n' "$name"
    done < <(aphotic_plugin_names)
}

# True (exit 0) only when aphotic.toml actually declares a [plugins]
# section -- distinguishes "nothing desired" from "desired: nothing",
# since an empty array is a real, meaningful desired state (uninstall
# everything) and an absent section means drift tracking is opted out.
_aphotic_state_plugins_declared() {
    local toml="${APHOTIC_DOTS_DIR}/aphotic.toml"
    [[ -f "$toml" ]] || return 1
    grep -qE '^\[plugins\][[:space:]]*$' "$toml"
}

# name<TAB>state, one per line: state is "ok" (desired and actual agree),
# "missing" (desired, not installed/enabled) or "extra" (installed and
# enabled, not desired). Callers needing just one side can grep the tab
# field rather than re-diffing.
_aphotic_state_plugin_drift() {
    _aphotic_state_plugins_declared || return 0

    local desired actual name
    desired="$(_aphotic_state_desired_plugins)"
    actual="$(_aphotic_state_actual_plugins)"

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if grep -qxF "$name" <<<"$actual"; then
            printf '%s\tok\n' "$name"
        else
            printf '%s\tmissing\n' "$name"
        fi
    done <<<"$desired"

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        grep -qxF "$name" <<<"$desired" || printf '%s\textra\n' "$name"
    done <<<"$actual"
}
