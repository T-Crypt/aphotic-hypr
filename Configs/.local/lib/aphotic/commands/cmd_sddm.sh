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

    # install.sh's install_sddm() chowns this whole theme directory to
    # the installing user right after extracting it (`sudo chown -R
    # "$USER:$USER" .../sugar-candy`) specifically so ordinary desktop
    # use doesn't need root after that point -- but this function always
    # wrapped its cp/sed in `sudo` regardless, which only ever succeeded
    # when a sudo credential happened to already be cached (e.g. right
    # after an interactive `sudo -v`/install run) and no-op'd silently on
    # every other automatic call (every theme/wallpaper change routes
    # through this as a best-effort background call -- see Wallpapers.qml/
    # cmd_theme.sh/wallswitcher.py), which is why this looked like it
    # needed a human to trigger it by hand. Try writing directly first --
    # correct and sudo-free on any machine that went through the normal
    # installer -- and only fall back to sudo (still best-effort, still
    # silently skips rather than blocking on a password prompt) for a
    # theme directory some other setup left root-owned.
    local filename; filename="$(basename "$image_path")"
    local dest_bg="${APHOTIC_SDDM_THEME_DIR}/Backgrounds/${filename}"
    local dest_conf="${APHOTIC_SDDM_THEME_DIR}/theme.conf"

    if [[ -w "${APHOTIC_SDDM_THEME_DIR}/Backgrounds" ]] && [[ -w "$dest_conf" ]]; then
        cp "$image_path" "${APHOTIC_SDDM_THEME_DIR}/Backgrounds/" &&
            sed -i "s|^Background=.*|Background=\"Backgrounds/${filename}\"|" "$dest_conf" &&
            aphotic_ok "sddm background synced to ${filename}"
        return
    fi

    if ! sudo -n true 2>/dev/null; then
        aphotic_warn "sddm theme directory isn't user-writable and no passwordless sudo is available (see commands/README.md); run 'aphotic sddm sync' manually, or 'sudo -v' first"
        return 0
    fi

    sudo cp "$image_path" "${APHOTIC_SDDM_THEME_DIR}/Backgrounds/" &&
        sudo sed -i "s|^Background=.*|Background=\"Backgrounds/${filename}\"|" "$dest_conf" &&
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

    # Same install.sh-chowns-the-theme-dir reasoning as _aphotic_sddm_sync
    # above -- only fall back to requiring sudo when theme.conf genuinely
    # isn't user-writable.
    local need_sudo="false"
    if [[ ! -w "$conf" ]]; then
        need_sudo="true"
        if ! sudo -n true 2>/dev/null; then
            aphotic_warn "sddm theme.conf isn't user-writable and no passwordless sudo is available (see commands/README.md); run 'sudo -v' first, then retry"
            return 0
        fi
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

    if [[ "$need_sudo" == "true" ]]; then
        sudo cp "$tmp" "$conf" && rm -f "$tmp" && aphotic_ok "sddm greeting set to: ${text}"
    else
        cp "$tmp" "$conf" && rm -f "$tmp" && aphotic_ok "sddm greeting set to: ${text}"
    fi
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
