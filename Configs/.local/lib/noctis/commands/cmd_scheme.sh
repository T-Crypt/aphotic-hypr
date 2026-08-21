#!/usr/bin/env bash
# noctis scheme — colour scheme control (static or matugen-style dynamic).
# @cmd: scheme
# @cmd.desc: Set the active colour scheme
# @cmd.opt: set -n <name> | Apply a named scheme

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

            # Set the active scheme in config
            noctis_json_set "scheme.active" "$name"

            # Get current theme to determine wallpaper for palette generation
            local current_theme=""
            if [[ -f "${NOCTIS_STATE_HOME}/active-theme" ]]; then
                current_theme=$(cat "${NOCTIS_STATE_HOME}/active-theme")
            fi

            # If we have an active theme, regenerate the palette
            if [[ -n "$current_theme" ]] && [[ -d "${NOCTIS_DATA_HOME}/themes/${current_theme}" ]]; then
                local wallpaper_file="${NOCTIS_DATA_HOME}/themes/${current_theme}/wallpaper.jpg"

                if [[ -f "$wallpaper_file" ]]; then
                    noctis_log "regenerating palette for scheme '${name}' using wallpaper: ${wallpaper_file}"

                    # Try to generate the palette with wallust (default engine)
                    if command -v wallust >/dev/null 2>&1; then
                        # Use wallust to regenerate colors based on current wallpaper
                        wallust run -i "$wallpaper_file" --config "${NOCTIS_CONFIG_HOME}/wallust.toml"
                        noctis_ok "palette regenerated for scheme '${name}'"
                    else
                        noctis_warn "wallust not found, skipping palette regeneration"
                    fi

                    # Reload the shell to apply new colors
                    source "${COMMANDS_DIR}/cmd_reload.sh"
                    noctis_cmd_reload --modules-only
                else
                    noctis_warn "no wallpaper found for current theme, skipping palette regeneration"
                fi
            else
                noctis_log "no active theme or wallpaper found, skipping palette regeneration"
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
