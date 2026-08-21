#!/usr/bin/env bash
# noctis theme — switch between installed Noctis themes.
# @cmd: theme
# @cmd.desc: List, set, or cycle themes
# @cmd.opt: list        | List installed themes
# @cmd.opt: set <name>  | Apply a theme by name
# @cmd.opt: next|prev   | Cycle to the next/previous theme

NOCTIS_THEMES_DIR="${NOCTIS_DATA_HOME}/themes"
NOCTIS_ACTIVE_THEME_FILE="${NOCTIS_STATE_HOME}/active-theme"

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

_noctis_theme_apply() {
    local theme_name="$1"

    # Validate theme exists
    if [[ ! -d "${NOCTIS_THEMES_DIR}/${theme_name}" ]]; then
        noctis_err "theme '${theme_name}' not found in ${NOCTIS_THEMES_DIR}"
        return 1
    fi

    # Create a symlink or copy to the active theme location that quickshell modules read from
    local active_theme_dir="${NOCTIS_DATA_HOME}/active-theme"

    # Remove existing symlink/dir if it exists
    if [[ -L "$active_theme_dir" ]] || [[ -d "$active_theme_dir" ]]; then
        rm -rf "$active_theme_dir"
    fi

    # Create symlink to the theme directory
    ln -s "${NOCTIS_THEMES_DIR}/${theme_name}" "$active_theme_dir"

    # Store the active theme name in a state file for cycling
    echo "$theme_name" > "$NOCTIS_ACTIVE_THEME_FILE"

    # Update config with active theme
    noctis_json_set "theme.active" "$theme_name"

    noctis_ok "applied theme '${theme_name}'"

    # Reload the shell modules to apply the new theme
    source "${COMMANDS_DIR}/cmd_reload.sh"
    noctis_cmd_reload --modules-only

    return 0
}

noctis_cmd_theme() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        list) _noctis_theme_list ;;
        set)
            local name="${1:-}"
            [[ -z "$name" ]] && { noctis_err "usage: noctis theme set <name>"; return 1; }

            # Apply the theme
            if _noctis_theme_apply "$name"; then
                noctis_ok "theme '${name}' applied successfully"
            else
                noctis_err "failed to apply theme '${name}'"
                return 1
            fi
            ;;
        next|prev)
            # Get current theme name from state file
            local current_theme=""
            if [[ -f "$NOCTIS_ACTIVE_THEME_FILE" ]]; then
                current_theme=$(cat "$NOCTIS_ACTIVE_THEME_FILE")
            fi

            # Get all themes
            local themes=()
            for dir in "$NOCTIS_THEMES_DIR"/*/; do
                [[ -d "$dir" ]] || continue
                themes+=("$(basename "$dir")")
            done

            if [[ ${#themes[@]} -eq 0 ]]; then
                noctis_err "no themes found in ${NOCTIS_THEMES_DIR}"
                return 1
            fi

            # Find current theme index
            local current_index=-1
            for i in "${!themes[@]}"; do
                if [[ "${themes[$i]}" == "$current_theme" ]]; then
                    current_index=$i
                    break
                fi
            done

            # Calculate next/prev index
            local new_index
            if [[ "$sub" == "next" ]]; then
                if [[ $current_index -eq -1 ]] || [[ $current_index -eq $((${#themes[@]} - 1)) ]]; then
                    new_index=0
                else
                    new_index=$((current_index + 1))
                fi
            else  # prev
                if [[ $current_index -eq -1 ]] || [[ $current_index -eq 0 ]]; then
                    new_index=$((${#themes[@]} - 1))
                else
                    new_index=$((current_index - 1))
                fi
            fi

            local new_theme="${themes[$new_index]}"

            if _noctis_theme_apply "$new_theme"; then
                noctis_ok "switched to theme '${new_theme}'"
            else
                noctis_err "failed to switch to theme '${new_theme}'"
                return 1
            fi
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
