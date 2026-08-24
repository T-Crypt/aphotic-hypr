#!/usr/bin/env bash
# aphotic wallpaper — set/cycle the wallpaper within the active theme.
# @cmd: wallpaper
# @cmd.desc: Set, randomize, or cycle the wallpaper
# @cmd.group: CONFIG
# @cmd.opt: -f, --file <path> | Set a specific wallpaper (must live under a theme folder)
# @cmd.opt: --random          | Pick a random wallpaper from the active theme
# @cmd.opt: --next            | Advance to another wallpaper in the active theme
# @cmd.opt: --fetch-extra [theme] | Download the larger community wallpaper pool (opt-in, see below)
# @cmd.opt: -y, --yes             | Skip the --fetch-extra confirmation prompt
#
# Wallpapers now live inside theme folders (APHOTIC_AWWW_DIR/<theme>/),
# see `aphotic theme`. --random/--next delegate to wallswitcher.py, the
# same script SUPER+W runs, so this stays a single source of truth for
# "pick another wallpaper in the current theme" instead of a second,
# divergent implementation.
#
# --fetch-extra covers the *rest* of the community wallpaper pool that
# doesn't ship in the repo itself, to keep a fresh `git clone` small for
# low-bandwidth installs: each theme folder ships 4-5 curated wallpapers
# committed directly, and `extra-wallpapers.json` (sitting alongside the
# theme folders) lists everything beyond that as {filename, size, sha256,
# source_url} pointing back at the original GitHub repos they came from
# -- nothing is re-hosted. This command reads that manifest and fetches
# on demand, verifying each download's sha256 before it's kept.

APHOTIC_AWWW_DIR="${APHOTIC_AWWW_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/awww}"
APHOTIC_WALLSWITCHER="${APHOTIC_DOTS_DIR}/Configs/hypr/scripts/wallswitcher.py"
APHOTIC_EXTRA_WALLPAPERS_MANIFEST="${APHOTIC_AWWW_DIR}/extra-wallpapers.json"

_aphotic_wallpaper_human_size() {
    # $1 = bytes
    awk -v b="$1" 'BEGIN { if (b >= 1000000) printf "%.1fMB", b/1000000; else printf "%.0fKB", b/1000 }'
}

_aphotic_wallpaper_fetch_extra() {
    local only_theme="${1:-}" skip_confirm="${2:-}"

    aphotic_require jq || return 1
    aphotic_require curl || return 1
    aphotic_require sha256sum || return 1

    [[ -f "$APHOTIC_EXTRA_WALLPAPERS_MANIFEST" ]] || {
        aphotic_err "manifest not found: ${APHOTIC_EXTRA_WALLPAPERS_MANIFEST}"
        return 1
    }

    local themes
    if [[ -n "$only_theme" ]]; then
        jq -e --arg t "$only_theme" 'has($t)' "$APHOTIC_EXTRA_WALLPAPERS_MANIFEST" >/dev/null 2>&1 || {
            aphotic_err "no such theme in manifest: ${only_theme}"
            return 1
        }
        themes="$only_theme"
    else
        themes="$(jq -r 'keys[]' "$APHOTIC_EXTRA_WALLPAPERS_MANIFEST")"
    fi

    # Only count entries not already present on disk -- re-running this
    # is idempotent and a second run should report accurately, not the
    # full pool size again.
    local total_bytes=0 total_count=0 theme entry_count
    while IFS= read -r theme; do
        entry_count="$(jq -r --arg t "$theme" '.[$t] | length' "$APHOTIC_EXTRA_WALLPAPERS_MANIFEST")"
        local i fname size
        for ((i = 0; i < entry_count; i++)); do
            fname="$(jq -r --arg t "$theme" --argjson i "$i" '.[$t][$i].filename' "$APHOTIC_EXTRA_WALLPAPERS_MANIFEST")"
            [[ -f "${APHOTIC_AWWW_DIR}/${theme}/${fname}" ]] && continue
            size="$(jq -r --arg t "$theme" --argjson i "$i" '.[$t][$i].size' "$APHOTIC_EXTRA_WALLPAPERS_MANIFEST")"
            total_bytes=$((total_bytes + size))
            total_count=$((total_count + 1))
        done
    done <<< "$themes"

    if [[ "$total_count" -eq 0 ]]; then
        aphotic_ok "extra wallpapers already downloaded, nothing to do"
        return 0
    fi

    aphotic_log "$(printf '%d wallpaper(s), %s to download' "$total_count" "$(_aphotic_wallpaper_human_size "$total_bytes")")"
    if [[ "$skip_confirm" != "yes" ]]; then
        aphotic_confirm "Download these now?" || { aphotic_log "skipped"; return 0; }
    fi

    local ok=0 failed=0
    while IFS= read -r theme; do
        entry_count="$(jq -r --arg t "$theme" '.[$t] | length' "$APHOTIC_EXTRA_WALLPAPERS_MANIFEST")"
        mkdir -p "${APHOTIC_AWWW_DIR}/${theme}"
        local i fname url sha dest tmp got_sha
        for ((i = 0; i < entry_count; i++)); do
            fname="$(jq -r --arg t "$theme" --argjson i "$i" '.[$t][$i].filename' "$APHOTIC_EXTRA_WALLPAPERS_MANIFEST")"
            dest="${APHOTIC_AWWW_DIR}/${theme}/${fname}"
            [[ -f "$dest" ]] && continue

            url="$(jq -r --arg t "$theme" --argjson i "$i" '.[$t][$i].source_url' "$APHOTIC_EXTRA_WALLPAPERS_MANIFEST")"
            sha="$(jq -r --arg t "$theme" --argjson i "$i" '.[$t][$i].sha256' "$APHOTIC_EXTRA_WALLPAPERS_MANIFEST")"
            tmp="$(mktemp)"

            if curl -fsSL -m 30 -o "$tmp" "$url" 2>/dev/null; then
                got_sha="$(sha256sum "$tmp" | cut -d' ' -f1)"
                if [[ "$got_sha" == "$sha" ]]; then
                    # mktemp defaults to 600 -- mv preserves that, which
                    # would otherwise leave every fetched wallpaper
                    # unreadable by anything running as another user
                    # (e.g. a display manager reading it for a login
                    # background) where every other file here is a normal
                    # 644.
                    chmod 644 "$tmp"
                    mv "$tmp" "$dest"
                    ok=$((ok + 1))
                else
                    aphotic_warn "checksum mismatch, skipping: ${theme}/${fname}"
                    rm -f "$tmp"
                    failed=$((failed + 1))
                fi
            else
                aphotic_warn "download failed: ${theme}/${fname}"
                rm -f "$tmp"
                failed=$((failed + 1))
            fi
        done
    done <<< "$themes"

    aphotic_ok "$(printf '%d downloaded' "$ok")$([[ "$failed" -gt 0 ]] && printf ', %d failed' "$failed")"
}

_aphotic_wallpaper_run_switcher() {
    if [[ -x "$APHOTIC_WALLSWITCHER" ]] || command -v python3 >/dev/null 2>&1; then
        python3 "$APHOTIC_WALLSWITCHER"
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
        --random|--next)
            _aphotic_wallpaper_run_switcher
            ;;
        --fetch-extra)
            local extra_theme="" skip_confirm="no"
            shift
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -y|--yes) skip_confirm="yes" ;;
                    -*) aphotic_err "unknown wallpaper option: $1"; return 1 ;;
                    *) extra_theme="$1" ;;
                esac
                shift
            done
            _aphotic_wallpaper_fetch_extra "$extra_theme" "$skip_confirm"
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: aphotic wallpaper -f <path> | --random | --next | --fetch-extra [theme] [-y]

  -f, --file <path>   Set a specific wallpaper (must be under ${APHOTIC_AWWW_DIR}/<theme>/)
  --random            Pick another wallpaper within the active theme
  --next              Same as --random (themes don't define wallpaper ordering)
  --fetch-extra [theme]  Download the larger community wallpaper pool (all
                          themes, or just one). Prompts with the total size
                          first; pass -y/--yes to skip the prompt.
HELP
            ;;
        *)
            aphotic_err "unknown wallpaper option: $1"
            return 1
            ;;
    esac
}
