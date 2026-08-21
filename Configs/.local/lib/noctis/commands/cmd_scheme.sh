#!/usr/bin/env bash
# noctis scheme — colour scheme control (static or matugen-style dynamic).
# @cmd: scheme
# @cmd.desc: Set the active colour scheme
# @cmd.group: CONFIG
# @cmd.opt: set -n <name> | Apply a named scheme
#
# Reads the active theme/wallpaper from the shared theme.json (the
# same state Themes.qml and wallswitcher.py read/write) rather than
# a separate active-theme file, so scheme changes regenerate the
# palette from whatever wallpaper is actually showing.

NOCTIS_AWWW_DIR="${NOCTIS_AWWW_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/awww}"
NOCTIS_THEME_STATE_FILE="${NOCTIS_STATE_HOME}/theme.json"

noctis_cmd_scheme() {
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
            [[ -z "$name" ]] && { noctis_err "usage: noctis scheme set -n <name>"; return 1; }

            noctis_json_set "scheme.active" "$name"

            local current_theme="" current_wallpaper=""
            if [[ -f "$NOCTIS_THEME_STATE_FILE" ]]; then
                current_theme="$(jq -r '.theme // ""' "$NOCTIS_THEME_STATE_FILE" 2>/dev/null)"
                current_wallpaper="$(jq -r '.wallpaper // ""' "$NOCTIS_THEME_STATE_FILE" 2>/dev/null)"
            fi

            if [[ -n "$current_theme" ]] && [[ -n "$current_wallpaper" ]] && [[ -f "${NOCTIS_AWWW_DIR}/${current_theme}/${current_wallpaper}" ]]; then
                local image_path="${NOCTIS_AWWW_DIR}/${current_theme}/${current_wallpaper}"

                if command -v wallust >/dev/null 2>&1; then
                    noctis_log "regenerating palette for scheme '${name}' using wallpaper: ${image_path}"

                    source "${COMMANDS_DIR}/cmd_theme.sh"
                    local backend palette
                    backend="$(_noctis_toml_get "${NOCTIS_AWWW_DIR}/${current_theme}/theme.toml" engine backend)"
                    palette="$(_noctis_toml_get "${NOCTIS_AWWW_DIR}/${current_theme}/theme.toml" engine palette)"

                    local wallust_cmd=(wallust run "$image_path")
                    [[ -n "$backend" ]] && wallust_cmd+=(-b "$backend")
                    [[ -n "$palette" ]] && wallust_cmd+=(-p "$palette")
                    "${wallust_cmd[@]}" && noctis_ok "palette regenerated for scheme '${name}'"
                else
                    noctis_warn "wallust not found, skipping palette regeneration"
                fi
            else
                noctis_log "no active theme/wallpaper found in ${NOCTIS_THEME_STATE_FILE}, skipping palette regeneration"
            fi

            noctis_ok "scheme set to '${name}' in config"
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: noctis scheme set -n <name>

  set -n <name>   Apply a named colour scheme
HELP
            ;;
        *)
            noctis_err "unknown scheme subcommand: $1"
            return 1
            ;;
    esac
}
