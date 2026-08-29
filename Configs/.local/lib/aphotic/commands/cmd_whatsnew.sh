#!/usr/bin/env bash
# aphotic whatsnew — Hyprland-native "what's new" banner on version bump.
# @cmd: whatsnew
# @cmd.desc: Show a release-notes banner if the installed version changed
# @cmd.group: LIFECYCLE
# @cmd.opt: --force | Show the current version's banner even if already seen

_APHOTIC_WHATSNEW_COLOR="rgb(ff5c78)"

aphotic_cmd_whatsnew() {
    local force=0
    for arg in "$@"; do
        case "$arg" in
            --force) force=1 ;;
            -h|--help)
                cat <<EOF
Usage: aphotic whatsnew [--force]

Shows a Hyprland-native banner (hyprctl notify) summarizing what changed,
the first time this version runs after an install/update. Silent no-op on
every later run of the same version, unless --force is passed.
EOF
                return 0
                ;;
            *) aphotic_warn "whatsnew: ignoring unknown flag '$arg'" ;;
        esac
    done

    aphotic_require hyprctl || return 1

    local last_seen_file="${APHOTIC_STATE_HOME}/last-seen-version"
    mkdir -p "$APHOTIC_STATE_HOME"

    local last_seen=""
    [[ -f "$last_seen_file" ]] && last_seen="$(<"$last_seen_file")"

    if [[ "$force" -eq 0 && "$last_seen" == "$APHOTIC_VERSION" ]]; then
        return 0
    fi

    local notes_file="${APHOTIC_DOTS_DIR}/RELEASE_NOTES.md"
    local blurb=""
    if [[ -f "$notes_file" ]]; then
        blurb="$(awk -v ver="## ${APHOTIC_VERSION}" '
            $0 == ver { found=1; next }
            found && /^## / { exit }
            found && NF { line = line == "" ? $0 : line " " $0 }
            END { print line }
        ' "$notes_file")"
    fi
    [[ -z "$blurb" ]] && blurb="See the README for what changed."

    # Only mark this version "seen" once the banner actually reached a
    # running Hyprland -- a fresh install calls this before Hyprland has
    # ever started, where hyprctl has nothing to talk to and this fails.
    # Leaving last-seen-version untouched there means the next real
    # trigger (Hyprland's own startup.lua, right after) retries instead
    # of silently skipping the one banner the user would actually see.
    if hyprctl notify -1 15000 "$_APHOTIC_WHATSNEW_COLOR" "Aphotic v${APHOTIC_VERSION} — ${blurb}" >/dev/null 2>&1; then
        echo "$APHOTIC_VERSION" > "$last_seen_file"
    fi
}
