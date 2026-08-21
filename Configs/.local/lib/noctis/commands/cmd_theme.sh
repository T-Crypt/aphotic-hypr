#!/usr/bin/env bash
# noctis theme — switch between installed Noctis themes.
# @cmd: theme
# @cmd.desc: List, set, or cycle themes
# @cmd.group: CONFIG
# @cmd.opt: list        | List installed themes
# @cmd.opt: set <name>  | Apply a theme by name
# @cmd.opt: next|prev   | Cycle to the next/previous theme
#
# Themes live as directories under NOCTIS_AWWW_DIR, each with a
# theme.toml manifest (see Noctis-Hypr/themes/THEME_SPEC.md) — this is
# the same layout Themes.qml scans and the same state file
# (theme.json) that Themes.qml and wallswitcher.py read/write, so the
# CLI, the launcher, and the SUPER+W keybind all stay in sync.

NOCTIS_AWWW_DIR="${NOCTIS_AWWW_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/awww}"
NOCTIS_THEME_STATE_FILE="${NOCTIS_STATE_HOME}/theme.json"

# Extract a single flat key from a theme.toml, e.g.:
#   _noctis_toml_get "$dir/theme.toml" wallpaper default
# Deliberately minimal — matches the flat (no arrays-of-tables, no
# multi-line strings) shape defined in THEME_SPEC.md, mirroring the
# hand-written parser in Themes.qml.
_noctis_toml_get() {
    local file="$1" section="$2" key="$3"
    [[ -f "$file" ]] || return 1
    awk -v section="[$section]" -v key="$key" '
        $0 == section { insec=1; next }
        /^\[/ { insec=0 }
        insec && $0 ~ "^[[:space:]]*"key"[[:space:]]*=" {
            sub(/^[^=]*=[[:space:]]*/, "");
            gsub(/^"|"$/, "");
            print;
            exit
        }
    ' "$file"
}

_noctis_theme_dir() {
    printf '%s/%s' "$NOCTIS_AWWW_DIR" "$1"
}

_noctis_theme_wallpapers() {
    local dir; dir="$(_noctis_theme_dir "$1")"
    find "$dir" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -printf '%f\n' 2>/dev/null | sort
}

_noctis_theme_list() {
    mkdir -p "$NOCTIS_AWWW_DIR"
    local found=0
    for dir in "$NOCTIS_AWWW_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        found=1
        local name; name="$(basename "$dir")"
        local display; display="$(_noctis_toml_get "${dir}theme.toml" theme display_name)"
        printf '%s%s\n' "$name" "${display:+  ($display)}"
    done
    if [[ "$found" -eq 0 ]]; then
        noctis_log "no theme folders found in ${NOCTIS_AWWW_DIR}"
    fi
}

# Read {theme, wallpaper} out of theme.json. Prints two lines: theme, wallpaper.
_noctis_theme_read_state() {
    if [[ -f "$NOCTIS_THEME_STATE_FILE" ]]; then
        jq -r '.theme // "", .wallpaper // ""' "$NOCTIS_THEME_STATE_FILE" 2>/dev/null
    else
        printf '\n\n'
    fi
}

_noctis_theme_write_state() {
    local theme="$1" wallpaper="$2" tmp
    tmp="$(mktemp)"
    jq -n --arg t "$theme" --arg w "$wallpaper" '{theme: $t, wallpaper: $w}' > "$tmp" && mv "$tmp" "$NOCTIS_THEME_STATE_FILE"
}

# Apply theme_name/wallpaper_file: run awww + wallust with any engine
# pins from theme.toml, then persist state. wallpaper_file may be
# empty to fall back to the theme's declared default (or its first
# wallpaper alphabetically).
_noctis_theme_apply() {
    local theme_name="$1" wallpaper_file="${2:-}"
    local dir; dir="$(_noctis_theme_dir "$theme_name")"

    if [[ ! -d "$dir" ]]; then
        noctis_err "theme '${theme_name}' not found in ${NOCTIS_AWWW_DIR}"
        return 1
    fi

    if [[ -z "$wallpaper_file" ]]; then
        wallpaper_file="$(_noctis_toml_get "${dir}/theme.toml" wallpaper default)"
    fi
    if [[ -z "$wallpaper_file" ]] || [[ ! -f "${dir}/${wallpaper_file}" ]]; then
        wallpaper_file="$(_noctis_theme_wallpapers "$theme_name" | head -n1)"
    fi
    if [[ -z "$wallpaper_file" ]]; then
        noctis_err "no wallpapers found in theme '${theme_name}'"
        return 1
    fi

    local image_path="${dir}/${wallpaper_file}"
    local backend palette colorscheme papirus_color
    backend="$(_noctis_toml_get "${dir}/theme.toml" engine backend)"
    palette="$(_noctis_toml_get "${dir}/theme.toml" engine palette)"
    colorscheme="$(_noctis_toml_get "${dir}/theme.toml" engine colorscheme)"
    papirus_color="$(_noctis_toml_get "${dir}/theme.toml" icons papirus_color)"

    noctis_require awww || return 1
    awww img "$image_path" --transition-type wipe --transition-angle 30 --transition-step 90

    if command -v wallust >/dev/null 2>&1; then
        if [[ -n "$colorscheme" ]]; then
            # Fixed palette pin (theme.toml's [engine].colorscheme) --
            # reads Configs/wallust/colorschemes/<name>.json instead of
            # deriving colors from the wallpaper image, for themes with a
            # real brand palette (e.g. HackTheBox's own green/navy scheme)
            # that shouldn't drift with whatever art ships as the default
            # wallpaper. backend/palette are image-generation-only knobs
            # and don't apply here.
            wallust cs "$colorscheme" --format pywal
        else
            local wallust_cmd=(wallust run "$image_path")
            [[ -n "$backend" ]] && wallust_cmd+=(-b "$backend")
            [[ -n "$palette" ]] && wallust_cmd+=(-p "$palette")
            "${wallust_cmd[@]}"
        fi
    else
        noctis_warn "wallust not found, skipping palette regeneration"
    fi

    cp "$image_path" "${NOCTIS_AWWW_DIR}/wallpaper.rofi" 2>/dev/null || true

    # Folder-icon accent pin (theme.toml's [icons].papirus_color) -- real
    # per-icon recoloring isn't possible with a normal icon theme (each
    # icon's colors are baked into its file), so this swaps Papirus's
    # folder icons between its ~16 preset colors to roughly match the
    # theme instead. papirus-folders writes under /usr/share/icons/, so
    # like cmd_sddm.sh's sync, it needs passwordless sudo to run
    # non-interactively from a theme switch -- warns and no-ops rather
    # than blocking on a password prompt if that's not set up.
    if [[ -n "$papirus_color" ]] && command -v papirus-folders >/dev/null 2>&1; then
        if sudo -n true 2>/dev/null; then
            sudo papirus-folders -C "$papirus_color" --theme Papirus-Dark -u 2>/dev/null || true
        else
            noctis_warn "papirus-folders needs passwordless sudo to run automatically (see commands/README.md); run 'sudo papirus-folders -C ${papirus_color} --theme Papirus-Dark' manually, or 'sudo -v' first"
        fi
    fi

    _noctis_theme_write_state "$theme_name" "$wallpaper_file"
    noctis_json_set "theme.active" "$theme_name"

    # Best-effort — see cmd_sddm.sh; silently no-ops without passwordless
    # sudo rather than blocking a theme switch on a password prompt.
    source "${COMMANDS_DIR}/cmd_sddm.sh" && _noctis_sddm_sync

    # Quickshell hot-reloads Themes.qml's state via FileView watchChanges
    # on theme.json — no explicit reload needed for the shell to pick
    # this up, only for anything that isn't already watching the file.
    return 0
}

noctis_cmd_theme() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        list) _noctis_theme_list ;;
        set)
            local name="${1:-}"
            [[ -z "$name" ]] && { noctis_err "usage: noctis theme set <name>"; return 1; }

            if _noctis_theme_apply "$name"; then
                noctis_ok "theme '${name}' applied successfully"
            else
                return 1
            fi
            ;;
        next|prev)
            local current_theme
            current_theme="$(_noctis_theme_read_state | head -n1)"

            local themes=()
            for dir in "$NOCTIS_AWWW_DIR"/*/; do
                [[ -d "$dir" ]] || continue
                themes+=("$(basename "$dir")")
            done

            if [[ ${#themes[@]} -eq 0 ]]; then
                noctis_err "no theme folders found in ${NOCTIS_AWWW_DIR}"
                return 1
            fi

            local current_index=-1
            for i in "${!themes[@]}"; do
                if [[ "${themes[$i]}" == "$current_theme" ]]; then
                    current_index=$i
                    break
                fi
            done

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
                return 1
            fi
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: noctis theme <list|set|next|prev> [name]

  list         List theme folders (${NOCTIS_AWWW_DIR})
  set <name>   Apply a theme (its declared default wallpaper)
  next / prev  Cycle themes
HELP
            ;;
        *)
            noctis_err "unknown theme subcommand: ${sub}"
            return 1
            ;;
    esac
}
