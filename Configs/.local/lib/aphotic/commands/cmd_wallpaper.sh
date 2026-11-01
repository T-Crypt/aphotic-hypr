#!/usr/bin/env bash
# aphotic wallpaper — set/cycle the wallpaper within the active theme.
# @cmd: wallpaper
# @cmd.desc: Set, randomize, or cycle the wallpaper
# @cmd.group: CONFIG
# @cmd.opt: -f, --file <path> | Set a specific wallpaper (must live under a theme folder)
# @cmd.opt: --random          | Pick a random wallpaper from the active theme
# @cmd.opt: --next            | Advance to the next wallpaper in the active theme, in order
# @cmd.opt: fetch [theme..] [--all] [--dry-run] | Download a theme's wallpapers from installed packs
# @cmd.opt: packs             | List installed wallpaper packs and what they cover
# @cmd.opt: index [theme..]   | Record image sizes so ultrawide screens get ultrawide images
#
# Wallpapers now live inside theme folders (APHOTIC_AWWW_DIR/<theme>/),
# see `aphotic theme`. --random/--next delegate to wallswitcher.py, the
# same script SUPER+W runs, so this stays a single source of truth for
# "pick another wallpaper in the current theme" instead of a second,
# divergent implementation.

APHOTIC_AWWW_DIR="${APHOTIC_AWWW_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/awww}"
APHOTIC_WALLSWITCHER="${APHOTIC_DOTS_DIR}/Configs/hypr/scripts/wallswitcher.py"
APHOTIC_WALLPAPER_PACKS="${APHOTIC_DOTS_DIR}/Configs/.local/lib/aphotic/wallpaper_packs.py"

_aphotic_wallpaper_run_switcher() {
    # $1 = "next" for a real ordered advance through the active theme's
    # own wallpaper list (wraps at the end), anything else (or omitted)
    # for a random pick -- see wallswitcher.py's main(). Used to be the
    # same call either way (--next was just an alias for random).
    local mode="${1:-random}"
    if [[ -x "$APHOTIC_WALLSWITCHER" ]] || command -v python3 >/dev/null 2>&1; then
        if [[ "$mode" == "next" ]]; then
            python3 "$APHOTIC_WALLSWITCHER" --next
        else
            python3 "$APHOTIC_WALLSWITCHER"
        fi
    else
        aphotic_err "wallswitcher.py not runnable: ${APHOTIC_WALLSWITCHER}"
        return 1
    fi
}

aphotic_cmd_wallpaper() {
    case "${1:-}" in
        -f|--file)
            local path="${2:-}"
            [[ -z "$path" || ! -f "$path" ]] && { aphotic_err "file not found: ${path}"; return 1; }

            # Infer theme from the wallpaper's parent directory so it
            # stays consistent with the awww/<theme>/ layout.
            local dir theme_name file_name
            dir="$(cd "$(dirname "$path")" && pwd)"
            theme_name="$(basename "$dir")"
            file_name="$(basename "$path")"

            if [[ "$(dirname "$dir")" != "$APHOTIC_AWWW_DIR" ]]; then
                aphotic_err "wallpaper must live under ${APHOTIC_AWWW_DIR}/<theme>/ (got: ${path})"
                return 1
            fi

            source "${COMMANDS_DIR}/cmd_theme.sh"
            if _aphotic_theme_apply "$theme_name" "$file_name"; then
                aphotic_ok "wallpaper set: ${theme_name}/${file_name}"
            else
                return 1
            fi
            ;;
        --random)
            _aphotic_wallpaper_run_switcher random
            ;;
        --next)
            _aphotic_wallpaper_run_switcher next
            ;;
        fetch|packs|index)
            aphotic_require python3 || return 1
            APHOTIC_AWWW_DIR="$APHOTIC_AWWW_DIR" python3 "$APHOTIC_WALLPAPER_PACKS" "$@"
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: aphotic wallpaper -f <path> | --random | --next | fetch | packs | index

  -f, --file <path>   Set a specific wallpaper (must be under ${APHOTIC_AWWW_DIR}/<theme>/)
  --random            Pick another wallpaper within the active theme
  --next              Advance to the next wallpaper in the theme's own
                       list (alphabetical, wraps at the end) -- a real
                       deterministic cycle, not a second random pick
  fetch [theme..]     Download wallpapers for the active theme (or the
                       named ones) from installed wallpaper packs. Each
                       file is checked against the pack's sha256 first.
                       --all covers every installed theme; --dry-run
                       lists what would download.
  packs               List installed packs and the themes they cover
  index [theme..]     Record image sizes so an ultrawide screen prefers
                       ultrawide images
HELP
            ;;
        *)
            aphotic_err "unknown wallpaper option: $1"
            return 1
            ;;
    esac
}
