#!/usr/bin/env bash
# noctis wallpaper — set/cycle the wallpaper, matching caelestia's `-f` flag.
# @cmd: wallpaper
# @cmd.desc: Set, randomize, or cycle the wallpaper
# @cmd.opt: -f, --file <path> | Set a specific wallpaper
# @cmd.opt: --random          | Pick a random wallpaper from NOCTIS_WALLPAPER_DIR
# @cmd.opt: --next            | Advance to the next wallpaper in the directory

NOCTIS_WALLPAPER_DIR="${NOCTIS_WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"

noctis_cmd_wallpaper() {
    case "${1:-}" in
        -f|--file)
            local path="${2:-}"
            [[ -z "$path" || ! -f "$path" ]] && { noctis_err "file not found: ${path}"; return 1; }
            noctis_json_set "wallpaper.current" "$path"
            noctis_ok "wallpaper set: ${path}"
            # TODO: call the actual setter (swww img / hyprpaper / quickshell IPC)
            source "${COMMANDS_DIR}/cmd_reload.sh"
            noctis_cmd_reload
            ;;
        --random)
            [[ -d "$NOCTIS_WALLPAPER_DIR" ]] || { noctis_err "no wallpaper dir: ${NOCTIS_WALLPAPER_DIR}"; return 1; }
            local pick
            pick="$(find "$NOCTIS_WALLPAPER_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | shuf -n1)"
            [[ -z "$pick" ]] && { noctis_err "no wallpapers found in ${NOCTIS_WALLPAPER_DIR}"; return 1; }
            noctis_cmd_wallpaper -f "$pick"
            ;;
        --next)
            noctis_warn "wallpaper --next: TODO — needs current-index tracking like theme next/prev"
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: noctis wallpaper -f <path> | --random | --next

  -f, --file <path>  Set a specific wallpaper
  --random            Pick randomly from ${NOCTIS_WALLPAPER_DIR}
  --next              Advance to the next wallpaper (TODO)
HELP
            ;;
        *)
            noctis_err "unknown wallpaper option: $1"
            return 1
            ;;
    esac
}
