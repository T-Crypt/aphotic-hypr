#!/usr/bin/env bash
# aphotic theme — switch between installed Aphotic themes.
# @cmd: theme
# @cmd.desc: List, set, cycle, or download themes
# @cmd.group: CONFIG
# @cmd.opt: list [--remote] [--json]  | List downloaded (or available-remote) themes
# @cmd.opt: set <name>                | Apply a theme by name
# @cmd.opt: next|prev                 | Cycle to the next/previous theme
# @cmd.opt: download <name>           | Download a theme from APHOTIC_THEMES_REPO
# @cmd.opt: update <name>|--all       | Refresh a downloaded theme's files from the repo
# @cmd.opt: remove <name>             | Delete a downloaded (non-core) theme
# @cmd.opt: ensure-default            | Apply the install-time theme if none is set yet (startup.lua only)
#
# Themes live as directories under APHOTIC_AWWW_DIR, each with a
# theme.toml manifest (see Aphotic-Hypr/themes/THEME_SPEC.md) — this is
# the same layout Themes.qml scans and the same state file
# (theme.json) that Themes.qml and wallswitcher.py read/write, so the
# CLI, the launcher, and the SUPER+W keybind all stay in sync.
#
# download/update/remove pull additional community themes from a remote
# aphotic-themes index -- same clone/pull-a-repo shape as `aphotic plugin
# install` (cmd_plugin.sh), but not the plugin system: no hooks, no
# capabilities, no enable/disable state. "Downloaded" just means the
# directory exists under APHOTIC_AWWW_DIR, same contract _aphotic_theme_list
# already uses -- there's no separate state file to track it.

APHOTIC_AWWW_DIR="${APHOTIC_AWWW_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/awww}"
APHOTIC_THEME_STATE_FILE="${APHOTIC_STATE_HOME}/theme.json"

# Themes that ship in this repo can never be taken out with `theme
# remove` -- read from the checked-out repo rather than hardcoded here,
# so this stays correct as the curated set changes instead of drifting.
APHOTIC_CORE_THEMES=()
if [[ -d "${APHOTIC_DOTS_DIR}/Configs/awww" ]]; then
    for _aphotic_core_dir in "${APHOTIC_DOTS_DIR}/Configs/awww"/*/; do
        [[ -d "$_aphotic_core_dir" ]] || continue
        APHOTIC_CORE_THEMES+=("$(basename "$_aphotic_core_dir")")
    done
    unset _aphotic_core_dir
fi

_aphotic_theme_is_core() {
    local name="$1" core
    for core in "${APHOTIC_CORE_THEMES[@]:-}"; do
        [[ "$core" == "$name" ]] && return 0
    done
    return 1
}

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

# `core` lets AppearancePane.qml badge community-downloaded themes
# without keeping its own duplicate copy of APHOTIC_CORE_THEMES.
_aphotic_theme_list_json() {
    aphotic_require jq || return 1
    mkdir -p "$APHOTIC_AWWW_DIR"
    local dir name display core entries=()
    for dir in "$APHOTIC_AWWW_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        name="$(basename "$dir")"
        display="$(_aphotic_toml_get "${dir}theme.toml" theme display_name)"
        core="false"
        _aphotic_theme_is_core "$name" && core="true"
        entries+=("$(jq -n --arg name "$name" --arg display_name "${display:-$name}" --argjson core "$core" \
            '{name: $name, display_name: $display_name, core: $core}')")
    done
    printf '%s\n' "${entries[@]:-}" | jq -s 'map(select(. != null))'
}

_aphotic_theme_list_remote_json() {
    aphotic_require curl || return 1
    curl -fsSL -m 10 "$APHOTIC_THEMES_INDEX_URL" 2>/dev/null || echo '{"themes": []}'
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

# `wallust cs <name>` resolves a scheme by name inside wallust's own
# config dir, so a theme's [engine].colorscheme / [palette].anchor file
# has to physically land here -- there's no path form to point elsewhere.
_aphotic_theme_schemes_dir() {
    printf '%s/wallust/colorschemes' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# A downloaded theme may ship <theme>/colorschemes/*.json for the palette
# it pins. Core themes get theirs from the dots repo, which the community
# ones have no way to write into, so the download installs them instead.
_aphotic_theme_install_colorschemes() {
    local dir="$1" schemes_dir scheme
    schemes_dir="$(_aphotic_theme_schemes_dir)"
    [[ -d "${dir}/colorschemes" ]] || return 0
    mkdir -p "$schemes_dir"
    for scheme in "${dir}/colorschemes"/*.json; do
        [[ -f "$scheme" ]] || continue
        cp "$scheme" "${schemes_dir}/$(basename "$scheme")"
    done
}

# Only the ones this theme actually put there. Compared by content
# rather than by name: ~/.config/wallust is a symlink into the dots
# checkout, so a shipped scheme and a core one live at the same path and
# no path test can tell them apart. An installed file that still matches
# what this theme ships came from this theme; anything edited since, or
# owned by something else, is left alone.
_aphotic_theme_remove_colorschemes() {
    local dir="$1" schemes_dir scheme
    schemes_dir="$(_aphotic_theme_schemes_dir)"
    [[ -d "${dir}/colorschemes" ]] || return 0
    for scheme in "${dir}/colorschemes"/*.json; do
        [[ -f "$scheme" ]] || continue
        cmp -s "$scheme" "${schemes_dir}/$(basename "$scheme")" || continue
        rm -f "${schemes_dir}/$(basename "$scheme")"
    done
}

# Clone APHOTIC_THEMES_REPO on first use, `git pull --ff-only` on later
# ones -- mirrors _aphotic_plugin_sync_repo (cmd_plugin.sh) exactly. A
# pull failure is non-fatal, falls through to whatever's on disk already.
_aphotic_theme_sync_repo() {
    aphotic_require git || return 1
    if [[ -d "${APHOTIC_THEMES_REPO}/.git" ]]; then
        echo "Updating theme repo: git -C ${APHOTIC_THEMES_REPO} pull --ff-only"
        git -C "$APHOTIC_THEMES_REPO" pull --ff-only || aphotic_err "pull failed — continuing with the existing local checkout at ${APHOTIC_THEMES_REPO}"
    else
        echo "Cloning theme repo: git clone ${APHOTIC_THEMES_GIT_URL} ${APHOTIC_THEMES_REPO}"
        git clone "$APHOTIC_THEMES_GIT_URL" "$APHOTIC_THEMES_REPO" || { aphotic_err "clone failed: ${APHOTIC_THEMES_GIT_URL}"; return 1; }
    fi
}

_aphotic_theme_download() {
    local name="$1" src dest
    [[ -n "$name" ]] || { aphotic_err "usage: aphotic theme download <name>"; return 1; }

    _aphotic_theme_sync_repo || return 1

    src="${APHOTIC_THEMES_REPO}/${name}"
    if [[ ! -d "$src" ]] || [[ ! -f "${src}/theme.toml" ]]; then
        aphotic_err "no theme '${name}' in ${APHOTIC_THEMES_REPO} (repo synced okay, but this name isn't in it — check 'aphotic theme list --remote')"
        return 1
    fi

    dest="$(_aphotic_theme_dir "$name")"
    if [[ -e "$dest" ]]; then
        aphotic_err "already downloaded: ${dest} (use 'aphotic theme update ${name}' to refresh it)"
        return 1
    fi

    echo "Downloading ${name}..."
    cp -r "$src" "$dest"
    _aphotic_theme_install_colorschemes "$dest"

    aphotic_ok "downloaded ${name}"
    echo "THEME DOWNLOADED: ${name}"
}

# Staged swap (never a naked `rm -rf` on the live directory) -- mirrors
# _aphotic_plugin_update_one's rename dance, minus the registry/harness
# bits that don't apply to a theme.
_aphotic_theme_update_one() {
    local name="$1" src dest staged previous
    dest="$(_aphotic_theme_dir "$name")"
    [[ -e "$dest" ]] || { aphotic_err "not downloaded: ${name}"; return 1; }

    src="${APHOTIC_THEMES_REPO}/${name}"
    if [[ ! -d "$src" ]] || [[ ! -f "${src}/theme.toml" ]]; then
        aphotic_err "no theme '${name}' in ${APHOTIC_THEMES_REPO}"
        return 1
    fi

    staged="${dest}.updating"
    rm -rf "$staged"
    if ! cp -r "$src" "$staged"; then
        rm -rf "$staged"
        aphotic_err "failed to stage update for ${name}, left the downloaded copy alone"
        return 1
    fi

    previous="${dest}.previous"
    rm -rf "$previous"
    if ! mv "$dest" "$previous"; then
        rm -rf "$staged"
        aphotic_err "could not move ${name}'s downloaded copy aside, left it alone"
        return 1
    fi
    if ! mv "$staged" "$dest"; then
        mv "$previous" "$dest"
        rm -rf "$staged"
        aphotic_err "could not swap in the update for ${name}, restored the downloaded copy"
        return 1
    fi
    rm -rf "$previous"
    _aphotic_theme_install_colorschemes "$dest"

    aphotic_ok "updated ${name}"
    echo "THEME UPDATED: ${name}"
}

_aphotic_theme_update() {
    local target="$1" rc=0
    [[ -n "$target" ]] || { aphotic_err "usage: aphotic theme update <name>|--all"; return 1; }

    _aphotic_theme_sync_repo || return 1

    if [[ "$target" != "--all" ]]; then
        _aphotic_theme_update_one "$target"
        return $?
    fi

    local dir name
    for dir in "$APHOTIC_AWWW_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        name="$(basename "$dir")"
        _aphotic_theme_is_core "$name" && continue
        _aphotic_theme_update_one "$name" || rc=1
    done
    return "$rc"
}

_aphotic_theme_remove() {
    local name="$1" dest
    [[ -n "$name" ]] || { aphotic_err "usage: aphotic theme remove <name>"; return 1; }
    if _aphotic_theme_is_core "$name"; then
        aphotic_err "${name} ships with Aphotic — not something 'theme remove' can take out"
        return 1
    fi

    dest="$(_aphotic_theme_dir "$name")"
    [[ -e "$dest" ]] || { aphotic_err "not downloaded: ${name}"; return 1; }

    local was_active; was_active="$(_aphotic_theme_read_state | head -n1)"
    _aphotic_theme_remove_colorschemes "$dest"
    rm -rf "$dest"
    aphotic_ok "removed ${name}"

    # Same alphabetically-first fallback _aphotic_theme_ensure_default
    # uses -- don't leave theme.json pointing at a theme that's gone.
    [[ "$was_active" == "$name" ]] || return 0
    local dir fallback=""
    for dir in "$APHOTIC_AWWW_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        fallback="$(basename "$dir")"
        break
    done
    if [[ -n "$fallback" ]]; then
        _aphotic_theme_apply "$fallback"
    else
        aphotic_warn "no themes remain in ${APHOTIC_AWWW_DIR}"
    fi
}

# Palette clamp (theme.toml's [palette] table -- see themes/THEME_SPEC.md).
# `wallust run` derives every slot from the image alone, so one odd colour
# in a wallpaper can drag a theme's accent well outside its own look. This
# pulls the raw derived palette back toward the theme's anchor palette by
# at most the declared per-theme margins and re-runs every template from
# the clamped result via `wallust cs` -- the same path [engine].colorscheme
# already uses, so nothing downstream knows clamping happened. Opt-in:
# themes with no [palette].anchor never reach here.
_aphotic_theme_clamp_palette() {
    local theme_name="$1" dir="$2"
    local anchor; anchor="$(_aphotic_toml_get "${dir}/theme.toml" palette anchor)"
    [[ -n "$anchor" ]] || return 0

    command -v python3 >/dev/null 2>&1 || {
        aphotic_warn "python3 not found, skipping palette clamp for '${theme_name}'"
        return 0
    }

    local schemes_dir; schemes_dir="$(_aphotic_theme_schemes_dir)"
    local anchor_file="${schemes_dir}/${anchor}.json"
    if [[ ! -f "$anchor_file" ]]; then
        aphotic_warn "theme '${theme_name}' pins [palette].anchor = '${anchor}' but ${anchor_file} is missing -- applying unclamped palette"
        return 0
    fi

    local raw="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors.json"
    if [[ ! -f "$raw" ]]; then
        aphotic_warn "no derived palette at ${raw} -- applying unclamped palette"
        return 0
    fi

    local max_hue max_sat max_light
    max_hue="$(_aphotic_toml_get "${dir}/theme.toml" palette max_hue_shift)"
    max_sat="$(_aphotic_toml_get "${dir}/theme.toml" palette max_sat_shift)"
    max_light="$(_aphotic_toml_get "${dir}/theme.toml" palette max_light_shift)"

    local live="${schemes_dir}/${theme_name}-live.json"
    local clamp_cmd=(python3 "${LIB_DIR}/palette_clamp.py" "$raw" "$anchor_file" -o "$live")
    [[ -n "$max_hue" ]] && clamp_cmd+=(--max-hue-shift "$max_hue")
    [[ -n "$max_sat" ]] && clamp_cmd+=(--max-sat-shift "$max_sat")
    [[ -n "$max_light" ]] && clamp_cmd+=(--max-light-shift "$max_light")

    if "${clamp_cmd[@]}"; then
        wallust cs "${theme_name}-live" --format pywal
    else
        aphotic_warn "palette clamp failed for '${theme_name}' -- applying unclamped palette"
    fi
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
    local backend palette colorscheme style papirus_color icon_theme cursor_theme gtk_theme engine_name scheme contrast
    backend="$(_aphotic_toml_get "${dir}/theme.toml" engine backend)"
    palette="$(_aphotic_toml_get "${dir}/theme.toml" engine palette)"
    colorscheme="$(_aphotic_toml_get "${dir}/theme.toml" engine colorscheme)"
    style="$(_aphotic_toml_get "${dir}/theme.toml" engine style)"
    papirus_color="$(_aphotic_toml_get "${dir}/theme.toml" icons papirus_color)"
    icon_theme="$(_aphotic_toml_get "${dir}/theme.toml" icons icon_theme)"
    cursor_theme="$(_aphotic_toml_get "${dir}/theme.toml" icons cursor_theme)"
    gtk_theme="$(_aphotic_toml_get "${dir}/theme.toml" gtk theme)"
    engine_name="$(_aphotic_toml_get "${dir}/theme.toml" engine name)"
    scheme="$(_aphotic_toml_get "${dir}/theme.toml" engine scheme)"
    contrast="$(_aphotic_toml_get "${dir}/theme.toml" engine contrast)"

    if [[ -n "$engine_name" && "$engine_name" != "wallust" && "$engine_name" != "matugen" ]]; then
        aphotic_warn "theme '${theme_name}' pins unknown [engine].name = '${engine_name}' -- using wallust"
    fi

    # [engine].colorscheme is a fixed palette with no image derivation at
    # all, so there's no raw palette for [palette].anchor to clamp.
    if [[ -n "$colorscheme" ]] && [[ -n "$(_aphotic_toml_get "${dir}/theme.toml" palette anchor)" ]]; then
        aphotic_warn "theme '${theme_name}' sets both [engine].colorscheme and [palette].anchor -- using the fixed colorscheme, skipping the clamp"
    fi

    aphotic_require awww || return 1
    awww img "$image_path" --transition-type wipe --transition-angle 30 --transition-step 90

    if [[ "$engine_name" == "matugen" ]]; then
        aphotic_matugen_run "$image_path" "$scheme" "$style" "$contrast" \
            || aphotic_warn "matugen failed for theme '${theme_name}', palette left unchanged"
    elif command -v wallust >/dev/null 2>&1; then
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
            _aphotic_theme_clamp_palette "$theme_name" "$dir"
        fi
    else
        aphotic_warn "wallust not found, skipping palette regeneration"
    fi

    cp "$image_path" "${APHOTIC_AWWW_DIR}/current-wallpaper" 2>/dev/null || true

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
        list)
            local remote="false" as_json="false"
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --remote) remote="true" ;;
                    --json) as_json="true" ;;
                esac
                shift
            done

            if [[ "$remote" == "true" ]]; then
                aphotic_require jq || return 1
                local data; data="$(_aphotic_theme_list_remote_json)"
                if [[ "$as_json" == "true" ]]; then
                    echo "$data" | jq '.themes // []'
                else
                    echo "$data" | jq -r '(.themes // [])[] | "\(.name)\t\(.display_name)\t\(.version)\t\(.wallpaper_count) wallpapers\t\(if .approx_size_bytes >= 1000000 then (.approx_size_bytes/1000000*10|round/10|tostring)+"MB" else ((.approx_size_bytes/1000|round)|tostring)+"KB" end)\t\(.description)"' | column -t -s $'\t'
                fi
            elif [[ "$as_json" == "true" ]]; then
                _aphotic_theme_list_json
            else
                _aphotic_theme_list
            fi
            ;;
        download) _aphotic_theme_download "${1:-}" ;;
        update) _aphotic_theme_update "${1:-}" ;;
        remove) _aphotic_theme_remove "${1:-}" ;;
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
Usage: aphotic theme <list|set|next|prev|download|update|remove|ensure-default> [args]

  list [--remote] [--json]  List theme folders (${APHOTIC_AWWW_DIR}), or
                             --remote: what's available from
                             APHOTIC_THEMES_INDEX_URL
  set <name>                Apply a theme (its declared default wallpaper)
  next / prev                Cycle themes
  download <name>            Download a theme from a local checkout of
                             aphotic-themes (APHOTIC_THEMES_REPO, default
                             ~/aphotic-themes)
  update <name>|--all       Refresh a downloaded theme's files from the
                             repo. --all updates every community-downloaded
                             theme (skips the ones that ship with Aphotic)
  remove <name>              Delete a downloaded theme; refuses to take out
                             one of the themes that ships with Aphotic
  ensure-default             Apply the install-time theme if none is set
                             yet (no-op once a theme has ever been
                             applied); called once from Hyprland's
                             startup.lua, not meant for everyday use
HELP
            ;;
        *)
            aphotic_err "unknown theme subcommand: ${sub}"
            return 1
            ;;
    esac
}
