#!/usr/bin/env bash
# aphotic theme — switch between installed Aphotic themes.
# @cmd: theme
# @cmd.desc: List, set, or cycle themes
# @cmd.group: CONFIG
# @cmd.opt: list           | List installed themes
# @cmd.opt: set <name>     | Apply a theme by name
# @cmd.opt: next|prev      | Cycle to the next/previous theme
# @cmd.opt: ensure-default | Apply the install-time theme if none is set yet (startup.lua only)
#
# Themes live as directories under APHOTIC_AWWW_DIR, each with a
# theme.toml manifest (see Aphotic-Hypr/themes/THEME_SPEC.md) — this is
# the same layout Themes.qml scans and the same state file
# (theme.json) that Themes.qml and wallswitcher.py read/write, so the
# CLI, the launcher, and the SUPER+W keybind all stay in sync.

APHOTIC_AWWW_DIR="${APHOTIC_AWWW_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/awww}"
APHOTIC_THEME_STATE_FILE="${APHOTIC_STATE_HOME}/theme.json"

# _aphotic_toml_get (the flat theme.toml reader) now lives in
# globalcontrol.sh, shared with cmd_plugin.sh's plugin.toml reading —
# kept the same name/signature here via this thin alias so the calls
# below didn't all need touching.
_aphotic_toml_get() { aphotic_toml_get "$@"; }

_aphotic_theme_dir() {
    printf '%s/%s' "$APHOTIC_AWWW_DIR" "$1"
}

_aphotic_theme_wallpapers() {
    local dir; dir="$(_aphotic_theme_dir "$1")"
    find "$dir" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -printf '%f\n' 2>/dev/null | sort
}

_aphotic_theme_list() {
    mkdir -p "$APHOTIC_AWWW_DIR"
    local found=0
    for dir in "$APHOTIC_AWWW_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        found=1
        local name; name="$(basename "$dir")"
        local display; display="$(_aphotic_toml_get "${dir}theme.toml" theme display_name)"
        printf '%s%s\n' "$name" "${display:+  ($display)}"
    done
    if [[ "$found" -eq 0 ]]; then
        aphotic_log "no theme folders found in ${APHOTIC_AWWW_DIR}"
    fi
}

# Read {theme, wallpaper} out of theme.json. Prints two lines: theme, wallpaper.
_aphotic_theme_read_state() {
    if [[ -f "$APHOTIC_THEME_STATE_FILE" ]]; then
        jq -r '.theme // "", .wallpaper // ""' "$APHOTIC_THEME_STATE_FILE" 2>/dev/null
    else
        printf '\n\n'
    fi
}

_aphotic_theme_write_state() {
    local theme="$1" wallpaper="$2" tmp
    tmp="$(mktemp)"
    jq -n --arg t "$theme" --arg w "$wallpaper" '{theme: $t, wallpaper: $w}' > "$tmp" && mv "$tmp" "$APHOTIC_THEME_STATE_FILE"
}

# Apply theme_name/wallpaper_file: run awww + wallust with any engine
# pins from theme.toml, then persist state. wallpaper_file may be
# empty to fall back to the theme's declared default (or its first
# wallpaper alphabetically).
_aphotic_theme_apply() {
    local theme_name="$1" wallpaper_file="${2:-}"
    local dir; dir="$(_aphotic_theme_dir "$theme_name")"

    if [[ ! -d "$dir" ]]; then
        aphotic_err "theme '${theme_name}' not found in ${APHOTIC_AWWW_DIR}"
        return 1
    fi

    if [[ -z "$wallpaper_file" ]]; then
        wallpaper_file="$(_aphotic_toml_get "${dir}/theme.toml" wallpaper default)"
    fi
    if [[ -z "$wallpaper_file" ]] || [[ ! -f "${dir}/${wallpaper_file}" ]]; then
        wallpaper_file="$(_aphotic_theme_wallpapers "$theme_name" | head -n1)"
    fi
    if [[ -z "$wallpaper_file" ]]; then
        aphotic_err "no wallpapers found in theme '${theme_name}'"
        return 1
    fi

    local image_path="${dir}/${wallpaper_file}"
    local backend palette colorscheme style papirus_color icon_theme cursor_theme gtk_theme engine_name
    backend="$(_aphotic_toml_get "${dir}/theme.toml" engine backend)"
    palette="$(_aphotic_toml_get "${dir}/theme.toml" engine palette)"
    colorscheme="$(_aphotic_toml_get "${dir}/theme.toml" engine colorscheme)"
    style="$(_aphotic_toml_get "${dir}/theme.toml" engine style)"
    papirus_color="$(_aphotic_toml_get "${dir}/theme.toml" icons papirus_color)"
    icon_theme="$(_aphotic_toml_get "${dir}/theme.toml" icons icon_theme)"
    cursor_theme="$(_aphotic_toml_get "${dir}/theme.toml" icons cursor_theme)"
    gtk_theme="$(_aphotic_toml_get "${dir}/theme.toml" gtk theme)"
    engine_name="$(_aphotic_toml_get "${dir}/theme.toml" engine name)"

    # [engine].name is documented (themes/THEME_SPEC.md) as accepting
    # "wallust" | "matugen", but nothing here (or in Themes.qml/
    # wallswitcher.py) has ever actually read it -- every apply path
    # always runs wallust regardless of what this key says, so a theme
    # pinning matugen silently got wallust instead with zero indication
    # anything was ignored. Not implementing matugen here (real, separate
    # follow-up work) -- just making the mismatch loud instead of silent.
    if [[ -n "$engine_name" && "$engine_name" != "wallust" ]]; then
        aphotic_warn "theme '${theme_name}' pins [engine].name = '${engine_name}', but only wallust is wired up -- using wallust anyway"
    fi

    aphotic_require awww || return 1
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
            [[ -n "$style" ]] && wallust_cmd+=(-S "$style")
            "${wallust_cmd[@]}"
        fi
    else
        aphotic_warn "wallust not found, skipping palette regeneration"
    fi

    cp "$image_path" "${APHOTIC_AWWW_DIR}/wallpaper.rofi" 2>/dev/null || true

    # Plugin theme-hooks (see docs/PLUGIN_SYSTEM.md) -- fire-and-forget,
    # the shared implementation (cmd_plugin.sh) already backgrounds each
    # hook with its own timeout, so this call itself returns immediately.
    source "${COMMANDS_DIR}/cmd_plugin.sh" && _aphotic_plugin_run_theme_hooks

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
            aphotic_warn "papirus-folders needs passwordless sudo to run automatically (see commands/README.md); run 'sudo papirus-folders -C ${papirus_color} --theme Papirus-Dark' manually, or 'sudo -v' first"
        fi
    fi

    # Icon/cursor/gtk-theme pin (theme.toml's [icons].icon_theme/
    # cursor_theme, [gtk].theme) -- see themes/THEME_SPEC.md. Only applies
    # while the matching Settings.qml *UserSet flag is still false (the
    # user hasn't manually picked one in Personalization). Patches
    # settings.json directly (not aphotic_json_set/APHOTIC_CONFIG_FILE --
    # that's a different file, ~/.config/aphotic/shell.json, unrelated to
    # Quickshell's own state) so a running shell (settings.json has
    # watchChanges: true) picks the change up live and it survives the
    # next restart either way; also applied directly here via gsettings/
    # hyprctl so it takes effect even if the shell isn't running at all.
    local settings_file="${APHOTIC_STATE_HOME}/settings.json"
    if command -v jq >/dev/null 2>&1 && [[ -f "$settings_file" ]]; then
        local icon_user_set cursor_user_set gtk_user_set
        icon_user_set="$(jq -r '.iconThemeUserSet // false' "$settings_file")"
        cursor_user_set="$(jq -r '.cursorThemeUserSet // false' "$settings_file")"
        gtk_user_set="$(jq -r '.gtkThemeUserSet // false' "$settings_file")"

        if [[ -n "$icon_theme" && "$icon_user_set" != "true" ]]; then
            local tmp; tmp="$(mktemp)"
            jq --arg v "$icon_theme" '.iconTheme = $v' "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
            gsettings set org.gnome.desktop.interface icon-theme "$icon_theme" 2>/dev/null || true
            for f in "${HOME}/.config/qt5ct/qt5ct.conf" "${HOME}/.config/qt6ct/qt6ct.conf"; do
                [[ -f "$f" ]] && sed -i "s/^icon_theme=.*/icon_theme=${icon_theme}/" "$f"
            done
        fi
        if [[ -n "$cursor_theme" && "$cursor_user_set" != "true" ]]; then
            local tmp; tmp="$(mktemp)"
            jq --arg v "$cursor_theme" '.cursorTheme = $v' "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
            hyprctl setcursor "$cursor_theme" "$(jq -r '.cursorSize // 24' "$settings_file")" 2>/dev/null || true
            gsettings set org.gnome.desktop.interface cursor-theme "$cursor_theme" 2>/dev/null || true
        fi
        if [[ -n "$gtk_theme" && "$gtk_user_set" != "true" ]]; then
            local tmp; tmp="$(mktemp)"
            jq --arg v "$gtk_theme" '.gtkTheme = $v' "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
            gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" 2>/dev/null || true
        fi
    fi

    _aphotic_theme_write_state "$theme_name" "$wallpaper_file"
    aphotic_json_set "theme.active" "$theme_name"

    # Best-effort — see cmd_sddm.sh; silently no-ops without passwordless
    # sudo rather than blocking a theme switch on a password prompt.
    source "${COMMANDS_DIR}/cmd_sddm.sh" && _aphotic_sddm_sync

    # Quickshell hot-reloads Themes.qml's state via FileView watchChanges
    # on theme.json — no explicit reload needed for the shell to pick
    # this up, only for anything that isn't already watching the file.
    return 0
}

# Applies the install-time-configured theme (aphotic.toml's [theme].name)
# if no theme has ever been set on this machine yet (no theme.json) --
# called once from Hyprland's startup.lua so a fresh install actually
# shows a wallpaper on first boot instead of "No wallpaper set" until
# SUPER+SHIFT+W is used manually. A no-op once theme.json exists, so a
# later Hyprland restart never clobbers a theme the user already
# switched to.
_aphotic_theme_ensure_default() {
    [[ -f "$APHOTIC_THEME_STATE_FILE" ]] && return 0

    # `awww img` needs the daemon's socket up; poll instead of assuming a
    # fixed startup.lua sleep was long enough on this machine.
    local waited=0
    while ! awww query -j &>/dev/null; do
        sleep 0.5
        waited=$((waited + 1))
        if [[ $waited -ge 20 ]]; then
            aphotic_warn "awww-daemon never came up after 10s, skipping first-boot theme apply"
            return 1
        fi
    done

    # Same fixed clone-path convention InstallProfile.qml uses for
    # aphotic.toml -- see that file's comment for why it's not derived
    # from the running script's own location.
    local toml="${HOME}/Aphotic-Hypr/aphotic.toml"
    local theme_name; theme_name="$(_aphotic_toml_get "$toml" theme name || true)"

    if [[ -z "$theme_name" ]] || [[ ! -d "$(_aphotic_theme_dir "$theme_name")" ]]; then
        local dir
        for dir in "$APHOTIC_AWWW_DIR"/*/; do
            [[ -d "$dir" ]] || continue
            theme_name="$(basename "$dir")"
            break
        done
    fi

    if [[ -z "$theme_name" ]]; then
        aphotic_err "no theme folders found in ${APHOTIC_AWWW_DIR}, nothing to apply"
        return 1
    fi

    _aphotic_theme_apply "$theme_name"
}

aphotic_cmd_theme() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        list) _aphotic_theme_list ;;
        ensure-default) _aphotic_theme_ensure_default ;;
        set)
            local name="${1:-}"
            [[ -z "$name" ]] && { aphotic_err "usage: aphotic theme set <name>"; return 1; }

            if _aphotic_theme_apply "$name"; then
                aphotic_ok "theme '${name}' applied successfully"
            else
                return 1
            fi
            ;;
        next|prev)
            local current_theme
            current_theme="$(_aphotic_theme_read_state | head -n1)"

            local themes=()
            for dir in "$APHOTIC_AWWW_DIR"/*/; do
                [[ -d "$dir" ]] || continue
                themes+=("$(basename "$dir")")
            done

            if [[ ${#themes[@]} -eq 0 ]]; then
                aphotic_err "no theme folders found in ${APHOTIC_AWWW_DIR}"
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

            if _aphotic_theme_apply "$new_theme"; then
                aphotic_ok "switched to theme '${new_theme}'"
            else
                return 1
            fi
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: aphotic theme <list|set|next|prev|ensure-default> [name]

  list            List theme folders (${APHOTIC_AWWW_DIR})
  set <name>      Apply a theme (its declared default wallpaper)
  next / prev     Cycle themes
  ensure-default  Apply the install-time theme if none is set yet (no-op
                  once a theme has ever been applied); called once from
                  Hyprland's startup.lua, not meant for everyday use
HELP
            ;;
        *)
            aphotic_err "unknown theme subcommand: ${sub}"
            return 1
            ;;
    esac
}
