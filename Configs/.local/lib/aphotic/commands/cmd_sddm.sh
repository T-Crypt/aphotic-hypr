#!/usr/bin/env bash
# aphotic sddm — keep the SDDM login background in sync with the active
# desktop wallpaper, and customize its greeting text.
# @cmd: sddm
# @cmd.desc: Sync the SDDM login background, set a custom greeting
# @cmd.group: CONFIG
# @cmd.opt: sync             | Copy the current wallpaper into the SDDM theme (default)
# @cmd.opt: greeting [text]  | Set (or print, with no text) the login screen's greeting
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

_aphotic_sddm_greeting() {
    local text="$*"
    local conf="${APHOTIC_SDDM_THEME_DIR}/theme.conf"

    if [[ ! -f "$conf" ]]; then
        aphotic_warn "sddm theme.conf not found at ${conf}, skipping"
        return 0
    fi

    if [[ -z "$text" ]]; then
        python3 -c '
import re, sys
m = re.search(r"^HeaderText=\"(.*)\"$", open(sys.argv[1]).read(), re.MULTILINE)
print(re.sub(r"\\(.)", r"\1", m.group(1)) if m else "")
' "$conf"
        return 0
    fi

    if ! sudo -n true 2>/dev/null; then
        aphotic_warn "sddm greeting needs passwordless sudo to run automatically (see commands/README.md); run 'sudo -v' first, then retry"
        return 0
    fi

    # Edited via python's own string handling, not sed -- HeaderText can
    # contain quotes/backslashes/&, all of which sed's replacement syntax
    # treats specially, so building a sed expression from arbitrary user
    # text is not safely escapable. Written to a throwaway temp file first
    # (owned by the current user) so only the final `cp` needs sudo,
    # matching the existing sudo-gated cp/sed pattern used for the
    # background sync above.
    local tmp; tmp="$(mktemp)"
    if ! python3 -c '
import re, sys
path, text, out = sys.argv[1], sys.argv[2], sys.argv[3]
content = open(path).read()
escaped = text.replace(chr(92), chr(92) * 2).replace(chr(34), chr(92) + chr(34))
line = "HeaderText=\"" + escaped + "\""
new_content, n = re.subn(r"^HeaderText=\".*\"$", lambda m: line, content, count=1, flags=re.MULTILINE)
if n == 0:
    sys.exit(1)
open(out, "w").write(new_content)
' "$conf" "$text" "$tmp"; then
        aphotic_err "could not find HeaderText= in ${conf}"
        rm -f "$tmp"
        return 1
    fi

    sudo cp "$tmp" "$conf" && rm -f "$tmp" && aphotic_ok "sddm greeting set to: ${text}"
}

aphotic_cmd_sddm() {
    local sub="${1:-sync}"
    case "$sub" in
        sync) _aphotic_sddm_sync ;;
        greeting) shift || true; _aphotic_sddm_greeting "$@" ;;
        ""|-h|--help)
            cat <<HELP
Usage: aphotic sddm [sync|greeting [text]]

  sync            Copy the current wallpaper (via 'awww query') into
                  ${APHOTIC_SDDM_THEME_DIR} and point theme.conf's Background= at it.
  greeting        Print the login screen's current greeting text (theme.conf's HeaderText=).
  greeting <text> Set the login screen's greeting text.
HELP
            ;;
        *)
            aphotic_err "unknown sddm subcommand: ${sub}"
            return 1
            ;;
    esac
}
