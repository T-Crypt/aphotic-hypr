#!/usr/bin/env bash
# aphotic scheme — colour scheme control (static or matugen-style dynamic).
# @cmd: scheme
# @cmd.desc: Set the active colour scheme
# @cmd.group: CONFIG
# @cmd.opt: set -n <name> | Apply a named scheme
#
# Reads the active theme/wallpaper from the shared theme.json (the
# same state Themes.qml and wallswitcher.py read/write) rather than
# a separate active-theme file, so scheme changes regenerate the
# palette from whatever wallpaper is actually showing.

APHOTIC_AWWW_DIR="${APHOTIC_AWWW_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/awww}"
APHOTIC_THEME_STATE_FILE="${APHOTIC_STATE_HOME}/theme.json"

aphotic_cmd_scheme() {
    case "${1:-}" in
        set)
            shift
            local name=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -n|--name) name="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done
            [[ -z "$name" ]] && { aphotic_err "usage: aphotic scheme set -n <name>"; return 1; }

            aphotic_json_set "scheme.active" "$name"

            local current_theme="" current_wallpaper=""
            if [[ -f "$APHOTIC_THEME_STATE_FILE" ]]; then
                current_theme="$(jq -r '.theme // ""' "$APHOTIC_THEME_STATE_FILE" 2>/dev/null)"
                current_wallpaper="$(jq -r '.wallpaper // ""' "$APHOTIC_THEME_STATE_FILE" 2>/dev/null)"
            fi

            if [[ -n "$current_theme" ]] && [[ -n "$current_wallpaper" ]] && [[ -f "${APHOTIC_AWWW_DIR}/${current_theme}/${current_wallpaper}" ]]; then
                local image_path="${APHOTIC_AWWW_DIR}/${current_theme}/${current_wallpaper}"

                if command -v wallust >/dev/null 2>&1; then
                    aphotic_log "regenerating palette for scheme '${name}' using wallpaper: ${image_path}"

                    source "${COMMANDS_DIR}/cmd_theme.sh"
                    local backend palette
                    backend="$(_aphotic_toml_get "${APHOTIC_AWWW_DIR}/${current_theme}/theme.toml" engine backend)"
                    palette="$(_aphotic_toml_get "${APHOTIC_AWWW_DIR}/${current_theme}/theme.toml" engine palette)"

                    local wallust_cmd=(wallust run "$image_path")
                    [[ -n "$backend" ]] && wallust_cmd+=(-b "$backend")
                    [[ -n "$palette" ]] && wallust_cmd+=(-p "$palette")
                    "${wallust_cmd[@]}" && aphotic_ok "palette regenerated for scheme '${name}'"
                else
                    aphotic_warn "wallust not found, skipping palette regeneration"
                fi
            else
                aphotic_log "no active theme/wallpaper found in ${APHOTIC_THEME_STATE_FILE}, skipping palette regeneration"
            fi

            aphotic_ok "scheme set to '${name}' in config"
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: aphotic scheme set -n <name>

  set -n <name>   Apply a named colour scheme
HELP
            ;;
        *)
            aphotic_err "unknown scheme subcommand: $1"
            return 1
            ;;
    esac
}
