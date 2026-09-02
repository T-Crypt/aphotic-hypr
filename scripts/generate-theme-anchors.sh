#!/usr/bin/env bash
# scripts/generate-theme-anchors.sh
#
# One-time (re-runnable) bootstrap for the palette-clamp anchors: for each
# theme under Configs/awww/, derive the palette of that theme's
# [wallpaper].default image and save it as
# Configs/wallust/colorschemes/<theme>-anchor.json (pywal format) -- the
# reference palette theme.toml's [palette].anchor points at. See
# themes/THEME_SPEC.md's "Clamped palettes" section.
#
# Generating an anchor does NOT opt a theme into clamping; that's a
# separate, deliberate edit to that theme's theme.toml.
#
# Every wallust invocation here runs against a throwaway config dir with
# exactly one template and a redirected XDG_CACHE_HOME, so running this
# never touches ~/.cache/wal/colors.json or re-themes the live session.
#
# Usage: scripts/generate-theme-anchors.sh [theme ...]   (default: all)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AWWW_DIR="$ROOT/Configs/awww"
SCHEMES_DIR="$ROOT/Configs/wallust/colorschemes"
TEMPLATES_DIR="$ROOT/Configs/wallust/templates"

command -v wallust >/dev/null 2>&1 || { echo "wallust not found"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -r "$TEMPLATES_DIR" "$TMP/templates"
OUT="$TMP/anchor.json"

toml_get() {
    # section, key -- same flat single-section-scan shape the other
    # theme.toml readers in this repo use.
    local file="$1" section="$2" key="$3"
    [[ -f "$file" ]] || return 0
    awk -v section="[$section]" -v key="$key" '
        /^[[:space:]]*\[/ { in_section = ($0 ~ "^[[:space:]]*\\" section) ; next }
        in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            sub(/^[^=]*=[[:space:]]*/, "")
            sub(/[[:space:]]*(#.*)?$/, "")
            gsub(/^"|"$/, "")
            print; exit
        }
    ' "$file"
}

mkdir -p "$SCHEMES_DIR"

themes=("$@")
if [[ ${#themes[@]} -eq 0 ]]; then
    themes=()
    for dir in "$AWWW_DIR"/*/; do
        [[ -d "$dir" ]] && themes+=("$(basename "$dir")")
    done
fi

for theme in "${themes[@]}"; do
    dir="$AWWW_DIR/$theme"
    toml="$dir/theme.toml"
    if [[ ! -d "$dir" ]]; then
        echo "skip ${theme}: no such theme"
        continue
    fi

    engine_name="$(toml_get "$toml" engine name)"
    colorscheme="$(toml_get "$toml" engine colorscheme)"
    if [[ "$engine_name" == "matugen" ]]; then
        echo "skip ${theme}: pins matugen (clamping is wallust-only)"
        continue
    fi
    if [[ -n "$colorscheme" ]]; then
        echo "skip ${theme}: pins [engine].colorscheme (nothing is derived to clamp)"
        continue
    fi

    wallpaper="$(toml_get "$toml" wallpaper default)"
    if [[ -z "$wallpaper" || ! -f "$dir/$wallpaper" ]]; then
        wallpaper="$(find "$dir" -maxdepth 1 -type f \
            \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) \
            -printf '%f\n' 2>/dev/null | sort | head -n1)"
    fi
    if [[ -z "$wallpaper" ]]; then
        echo "skip ${theme}: no wallpapers"
        continue
    fi

    backend="$(toml_get "$toml" engine backend)"
    palette="$(toml_get "$toml" engine palette)"
    style="$(toml_get "$toml" engine style)"

    # Same generation knobs as Configs/wallust/wallust.toml, but with a
    # single template so this run writes exactly one file, in $TMP.
    cat > "$TMP/wallust.toml" <<EOF
backend = "${backend:-fastresize}"
palette = "${palette:-kmeans}"
check_contrast = true

[templates]
anchor = { template = "colors-wal.json", target = "${OUT}" }
EOF

    cmd=(wallust run "$dir/$wallpaper" -d "$TMP" -s -w -q)
    [[ -n "$style" ]] && cmd+=(-S "$style")

    rm -f "$OUT"
    if XDG_CACHE_HOME="$TMP/cache" "${cmd[@]}" && [[ -f "$OUT" ]]; then
        cp "$OUT" "$SCHEMES_DIR/${theme}-anchor.json"
        echo "wrote Configs/wallust/colorschemes/${theme}-anchor.json  (from ${wallpaper})"
    else
        echo "FAILED ${theme}: wallust produced no palette for ${wallpaper}"
    fi
done
