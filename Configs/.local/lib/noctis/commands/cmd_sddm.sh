#!/usr/bin/env bash
# noctis sddm — keep the SDDM login background in sync with the active
# desktop wallpaper.
# @cmd: sddm
# @cmd.desc: Sync the SDDM login background to the current wallpaper
# @cmd.group: CONFIG
# @cmd.opt: sync   | Copy the current wallpaper into the SDDM theme (default)
#
# Absorbs the old standalone hypr/scripts/sddmwall.sh, wired as a
# best-effort call from every wallpaper-change path (noctis theme/
# wallpaper, wallswitcher.py, the QML wallpaper picker) instead of being
# a manual, unwired script. Requires passwordless sudo for the specific
# `cp`/`sed` calls below to actually run non-interactively from those
# hooks — see README.md for the sudoers snippet. Without it, this just
# warns and no-ops rather than blocking on a password prompt.

NOCTIS_SDDM_THEME_DIR="${NOCTIS_SDDM_THEME_DIR:-/usr/share/sddm/themes/sugar-candy}"

_noctis_sddm_current_wallpaper() {
    noctis_require awww || return 1
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

_noctis_sddm_sync() {
    if [[ ! -d "$NOCTIS_SDDM_THEME_DIR" ]]; then
        noctis_warn "sddm theme not found at ${NOCTIS_SDDM_THEME_DIR}, skipping sync"
        return 0
    fi

    local image_path
    image_path="$(_noctis_sddm_current_wallpaper)"
    if [[ -z "$image_path" ]]; then
        noctis_warn "could not determine the current wallpaper via 'awww query', skipping sddm sync"
        return 1
    fi

    if ! sudo -n true 2>/dev/null; then
        noctis_warn "sddm sync needs passwordless sudo to run automatically (see commands/README.md); run 'noctis sddm sync' manually, or 'sudo -v' first"
        return 0
    fi

    local filename; filename="$(basename "$image_path")"
    sudo cp "$image_path" "${NOCTIS_SDDM_THEME_DIR}/Backgrounds/" &&
        sudo sed -i "s|^Background=.*|Background=\"Backgrounds/${filename}\"|" "${NOCTIS_SDDM_THEME_DIR}/theme.conf" &&
        noctis_ok "sddm background synced to ${filename}"
}

noctis_cmd_sddm() {
    local sub="${1:-sync}"
    case "$sub" in
        sync) _noctis_sddm_sync ;;
        ""|-h|--help)
            cat <<HELP
Usage: noctis sddm [sync]

  sync   Copy the current wallpaper (via 'awww query') into
         ${NOCTIS_SDDM_THEME_DIR} and point theme.conf's Background= at it.
HELP
            ;;
        *)
            noctis_err "unknown sddm subcommand: ${sub}"
            return 1
            ;;
    esac
}
