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

# name<TAB>state, one per line:
#   ok       desired, installed, enabled -- nothing to do
#   disabled desired, installed, but disabled -- `aphotic plugin enable`
#   missing  desired, not installed at all -- `aphotic plugin install`
#   extra    installed and enabled, not desired -- `aphotic plugin disable`
# disabled and missing need different actions (install refuses on an
# already-installed plugin), so callers converging state -- reconcile --
# must not collapse them into one "absent" bucket.
_aphotic_state_plugin_drift() {
    _aphotic_state_plugins_declared || return 0

    local desired installed actual name
    desired="$(_aphotic_state_desired_plugins)"
    installed="$(aphotic_plugin_names)"
    actual="$(_aphotic_state_actual_plugins)"

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if grep -qxF "$name" <<<"$actual"; then
            printf '%s\tok\n' "$name"
        elif grep -qxF "$name" <<<"$installed"; then
            printf '%s\tdisabled\n' "$name"
        else
            printf '%s\tmissing\n' "$name"
        fi
    done <<<"$desired"

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        grep -qxF "$name" <<<"$desired" || printf '%s\textra\n' "$name"
    done <<<"$actual"
}

# Structured git-drift facts for the dots checkout, one tab-separated
# record: <status>\t<branch>\t<head>\t<behind>
#   status: notgit | not-main | no-origin-ref | ok | behind
#   behind: commit count when status=behind, empty otherwise
# No network call -- compares against whatever origin/main was cached by
# the last `git fetch`, so this stays fast and safe to run anytime.
# Shared by `aphotic doctor`, `aphotic status` and `aphotic diff` so the
# three surfaces can't drift from each other on what "behind" means.
_aphotic_state_version_drift() {
    local dots="$APHOTIC_DOTS_DIR" branch head behind

    # -d "$dots/.git" would miss a git worktree checkout -- .git there is
    # a file (a "gitdir:" pointer back at the real repo), not a
    # directory. rev-parse is the check that's actually true for both.
    git -C "$dots" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        printf 'notgit\t\t\t\n'
        return 0
    }

    branch="$(git -C "$dots" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    head="$(git -C "$dots" rev-parse --short HEAD 2>/dev/null)"

    [[ "$branch" == "main" ]] || {
        printf 'not-main\t%s\t%s\t\n' "${branch:-?}" "${head:-?}"
        return 0
    }

    git -C "$dots" rev-parse --verify -q origin/main >/dev/null 2>&1 || {
        printf 'no-origin-ref\t%s\t%s\t\n' "$branch" "$head"
        return 0
    }

    behind="$(git -C "$dots" rev-list --count HEAD..origin/main 2>/dev/null)"
    if [[ -n "$behind" && "$behind" -gt 0 ]]; then
        printf 'behind\t%s\t%s\t%s\n' "$branch" "$head" "$behind"
    else
        printf 'ok\t%s\t%s\t0\n' "$branch" "$head"
    fi
}

# Structured service facts, one tab-separated record per line:
# <check>\t<state>\t<detail>
#   daemon: running | stopped
#   shellunit: enabled | disabled | missing (detail on disabled/missing)
#   displaymanager: ok | conflict (detail: which two)
# Not a new desired-state format -- just what `aphotic doctor` already
# knew how to check, exposed so `aphotic status`/`aphotic diff` can ask
# the same question instead of re-deriving it.
_aphotic_state_service_drift() {
    if pgrep -f "qs -c aphotic" >/dev/null 2>&1; then
        printf 'daemon\trunning\t\n'
    else
        printf 'daemon\tstopped\t\n'
    fi

    # `daemon` above only asks "is a qs process running right now" --
    # true for a manually-launched or fallback-relaunched shell just the
    # same as a systemd-supervised one, so it can't tell the two apart.
    # A qs process that isn't aphotic-shell.service won't auto-restart on
    # crash and won't come back on next login without a manual `aphotic
    # reload`/relaunch, which is exactly the gap this closes.
    if ! systemctl --user list-unit-files aphotic-shell.service &>/dev/null; then
        printf 'shellunit\tmissing\tnot deployed -- the shell won'"'"'t auto-start or auto-restart on crash; run install.sh --config-only to deploy it\n'
    elif ! systemctl --user is-enabled aphotic-shell.service &>/dev/null; then
        printf 'shellunit\tdisabled\tdeployed but not enabled -- run: systemctl --user enable --now aphotic-shell.service\n'
    else
        printf 'shellunit\tenabled\t\n'
    fi

    local sddm_enabled greetd_enabled
    sddm_enabled="$(systemctl is-enabled sddm.service 2>/dev/null)" || true
    greetd_enabled="$(systemctl is-enabled greetd.service 2>/dev/null)" || true
    if [[ "$sddm_enabled" == "enabled" && "$greetd_enabled" == "enabled" ]]; then
        printf 'displaymanager\tconflict\tboth sddm and greetd enabled -- only one owns display-manager.service\n'
    else
        printf 'displaymanager\tok\t\n'
    fi
}
