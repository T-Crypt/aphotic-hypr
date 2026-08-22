#!/usr/bin/env bash
# aphotic sddm — keep the SDDM login background in sync with the active
# desktop wallpaper.
# @cmd: sddm
# @cmd.desc: Sync the SDDM login background to the current wallpaper
# @cmd.group: CONFIG
# @cmd.opt: sync   | Copy the current wallpaper into the SDDM theme (default)
#
# Absorbs the old standalone hypr/scripts/sddmwall.sh, wired as a
# best-effort call from every wallpaper-change path (aphotic theme/
# wallpaper, wallswitcher.py, the QML wallpaper picker) instead of being
# a manual, unwired script. Requires passwordless sudo for the specific
# `cp`/`sed` calls below to actually run non-interactively from those
# hooks — see README.md for the sudoers snippet. Without it, this just
# warns and no-ops rather than blocking on a password prompt.

APHOTIC_SDDM_THEME_DIR="${APHOTIC_SDDM_THEME_DIR:-/usr/share/sddm/themes/sugar-candy}"

_aphotic_sddm_current_wallpaper() {
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

_aphotic_sddm_sync() {
    if [[ ! -d "$APHOTIC_SDDM_THEME_DIR" ]]; then
        aphotic_warn "sddm theme not found at ${APHOTIC_SDDM_THEME_DIR}, skipping sync"
        return 0
    fi

    local image_path
    image_path="$(_aphotic_sddm_current_wallpaper)"
    if [[ -z "$image_path" ]]; then
        aphotic_warn "could not determine the current wallpaper via 'awww query', skipping sddm sync"
        return 1
    fi

    if ! sudo -n true 2>/dev/null; then
        aphotic_warn "sddm sync needs passwordless sudo to run automatically (see commands/README.md); run 'aphotic sddm sync' manually, or 'sudo -v' first"
        return 0
    fi

    local filename; filename="$(basename "$image_path")"
    sudo cp "$image_path" "${APHOTIC_SDDM_THEME_DIR}/Backgrounds/" &&
        sudo sed -i "s|^Background=.*|Background=\"Backgrounds/${filename}\"|" "${APHOTIC_SDDM_THEME_DIR}/theme.conf" &&
        aphotic_ok "sddm background synced to ${filename}"
}

aphotic_cmd_sddm() {
    local sub="${1:-sync}"
    case "$sub" in
        sync) _aphotic_sddm_sync ;;
        ""|-h|--help)
            cat <<HELP
Usage: aphotic sddm [sync]

  sync   Copy the current wallpaper (via 'awww query') into
         ${APHOTIC_SDDM_THEME_DIR} and point theme.conf's Background= at it.
HELP
            ;;
        *)
            aphotic_err "unknown sddm subcommand: ${sub}"
            return 1
            ;;
    esac
}
