#!/usr/bin/env bash
# noctis theme — switch between installed Noctis themes.
# @cmd: theme
# @cmd.desc: List, set, or cycle themes
# @cmd.opt: list        | List installed themes
# @cmd.opt: set <name>  | Apply a theme by name
# @cmd.opt: next|prev   | Cycle to the next/previous theme

NOCTIS_THEMES_DIR="${NOCTIS_DATA_HOME}/themes"

_noctis_theme_list() {
    mkdir -p "$NOCTIS_THEMES_DIR"
    local found=0
    for dir in "$NOCTIS_THEMES_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        found=1
        basename "$dir"
    done
    [[ "$found" -eq 0 ]] && noctis_log "no themes installed in ${NOCTIS_THEMES_DIR}"
}

noctis_cmd_theme() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        list) _noctis_theme_list ;;
        set)
            local name="${1:-}"
            [[ -z "$name" ]] && { noctis_err "usage: noctis theme set <name>"; return 1; }
            # TODO: symlink/copy $NOCTIS_THEMES_DIR/<name> into the active
            # slot the quickshell modules read from, then reload.
            noctis_json_set "theme.active" "$name"
            noctis_log "theme set to '${name}' in config — wire up actual asset swap (TODO)"
            source "${COMMANDS_DIR}/cmd_reload.sh"
            noctis_cmd_reload
            ;;
        next|prev)
            noctis_warn "theme ${sub}: TODO — needs ordered theme list + current-index tracking"
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: noctis theme <list|set|next|prev> [name]

  list         List installed themes (${NOCTIS_THEMES_DIR})
  set <name>   Apply a theme
  next / prev  Cycle themes
HELP
            ;;
        *)
            noctis_err "unknown theme subcommand: ${sub}"
            return 1
            ;;
    esac
}
