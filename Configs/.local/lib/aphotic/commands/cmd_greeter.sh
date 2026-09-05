#!/usr/bin/env bash
# aphotic greeter — keep the greetd/Quickshell login greeter's palette and
# wallpaper in sync with the active desktop theme.
# @cmd: greeter
# @cmd.desc: Sync the greetd greeter's palette snapshot and wallpaper
# @cmd.group: CONFIG
# @cmd.opt: sync | Copy the current palette/wallpaper into the greeter snapshot (default)
#
# The greetd greeter (Configs/greetd/greeter/) runs as the unprivileged
# `greeter` system user, which has no access to any real user's
# ~/.local/state/aphotic/palette.json or ~/.config/awww/current-wallpaper —
# see that tree's own Colours.qml/Wallpaper.qml header comments. This is the
# analogue of cmd_sddm.sh for that surface: a root-owned, world-readable
# snapshot under /etc/aphotic/greeter/, wired as a best-effort call from the
# same wallpaper/theme-change paths as the sddm sync. Requires passwordless
# sudo for the specific cp/tee calls below to run non-interactively from
# those hooks — see README.md for the sudoers snippet. Without it, this
# just warns and no-ops rather than blocking on a password prompt.

APHOTIC_GREETER_SNAPSHOT_DIR="${APHOTIC_GREETER_SNAPSHOT_DIR:-/etc/aphotic/greeter}"

_aphotic_greeter_current_wallpaper() {
    aphotic_require awww || return 1
    awww query -j 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for outputs in data.values():
    for output in outputs:
        image = output.get("displaying", {}).get("image")
        if image:
            print(image)
            sys.exit(0)
'
}

# Maps the same ~/.local/state/aphotic/palette.json this machine's live
# Colours.qml reads onto the greeter's own flat schema (background/surface/
# textColor/mutedTextColor/primary/primaryTextColor/error) -- jq resolves
# matugen's real roles first and falls back to wallust's ANSI colors, the
# same precedence Colours.qml's own _role()/_rawColor() chain uses, so no
# engine branching needs duplicating here. Missing keys are dropped rather
# than written as null, so the greeter's own hardcoded fallback palette
# still wins for anything this pass can't resolve.
_aphotic_greeter_palette_json() {
    local src="${APHOTIC_STATE_HOME:-$HOME/.local/state/aphotic}/palette.json"
    [[ -f "$src" ]] || return 1
    jq -n --slurpfile p "$src" '
        ($p[0]) as $d |
        {
            background: ($d.surfaceContainer // $d.colors.color0),
            surface: ($d.surfaceContainerHigh // $d.colors.color0),
            textColor: ($d.roles.onSurface // $d.foreground // $d.colors.color7),
            mutedTextColor: ($d.roles.onSurfaceVariant // $d.colors.color8),
            primary: ($d.roles.primary // $d.colors.color4),
            primaryTextColor: $d.roles.onPrimary,
            error: ($d.roles.error // $d.colors.color1)
        } | with_entries(select(.value != null))
    ' 2>/dev/null
}

_aphotic_greeter_write() {
    local dest="$1" tmp="$2"
    if [[ -w "$(dirname "$dest")" ]] && { [[ ! -e "$dest" ]] || [[ -w "$dest" ]]; }; then
        cp "$tmp" "$dest"
        return $?
    fi
    if ! sudo -n true 2>/dev/null; then
        return 2
    fi
    sudo cp "$tmp" "$dest"
}

_aphotic_greeter_sync() {
    if [[ ! -d "$APHOTIC_GREETER_SNAPSHOT_DIR" ]]; then
        aphotic_warn "greeter snapshot dir not found at ${APHOTIC_GREETER_SNAPSHOT_DIR}; run install.sh's greetd opt-in first, skipping sync"
        return 0
    fi

    local wrote_any=0

    local palette; palette="$(_aphotic_greeter_palette_json)"
    if [[ -n "$palette" && "$palette" != "{}" ]]; then
        local tmp; tmp="$(mktemp)"
        printf '%s\n' "$palette" > "$tmp"
        if _aphotic_greeter_write "${APHOTIC_GREETER_SNAPSHOT_DIR}/palette.json" "$tmp"; then
            aphotic_ok "greeter palette synced"
            wrote_any=1
        else
            aphotic_warn "greeter snapshot dir isn't writable and no passwordless sudo is available (see commands/README.md); run 'aphotic greeter sync' manually, or 'sudo -v' first"
        fi
        rm -f "$tmp"
    fi

    local image_path; image_path="$(_aphotic_greeter_current_wallpaper)"
    if [[ -n "$image_path" && -f "$image_path" ]]; then
        if _aphotic_greeter_write "${APHOTIC_GREETER_SNAPSHOT_DIR}/wallpaper.png" "$image_path"; then
            aphotic_ok "greeter wallpaper synced"
            wrote_any=1
        fi
    fi

    [[ "$wrote_any" == "1" ]] || aphotic_warn "nothing to sync (no palette.json yet and/or 'awww query' returned no wallpaper)"
}

aphotic_cmd_greeter() {
    local sub="${1:-sync}"
    case "$sub" in
        sync) _aphotic_greeter_sync ;;
        ""|-h|--help)
            cat <<HELP
Usage: aphotic greeter [sync]

  sync   Copy the current palette (~/.local/state/aphotic/palette.json) and
         wallpaper (via 'awww query') into ${APHOTIC_GREETER_SNAPSHOT_DIR}
         for the greetd greeter to read. Default action if no subcommand is given.
HELP
            ;;
        *)
            aphotic_err "unknown greeter subcommand: ${sub}"
            return 1
            ;;
    esac
}
