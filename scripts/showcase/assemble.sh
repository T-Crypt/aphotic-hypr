#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$REPO_ROOT/recordings"
RAW="$OUT_DIR/aphotic-showcase-raw.mp4"
FINAL="$OUT_DIR/aphotic-showcase.mp4"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if ! command -v ffmpeg >/dev/null 2>&1; then
    printf 'ffmpeg not found on PATH. Install it first (pacman -S ffmpeg).\n' >&2
    exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
    printf 'ffprobe not found on PATH (ships with ffmpeg). Install ffmpeg first.\n' >&2
    exit 1
fi

if [[ ! -f "$RAW" ]]; then
    printf 'No raw recording at %s -- run scripts/showcase/record.sh first.\n' "$RAW" >&2
    exit 1
fi

BANNER_SVG="$REPO_ROOT/assets/aphotic-banner.svg"
if [[ ! -f "$BANNER_SVG" ]]; then
    printf 'Missing %s -- expected the project banner asset.\n' "$BANNER_SVG" >&2
    exit 1
fi

if command -v rsvg-convert >/dev/null 2>&1; then
    SVG_RENDER=(rsvg-convert -w 1800 -o)
elif command -v inkscape >/dev/null 2>&1; then
    SVG_RENDER=(inkscape -w 1800 -o)
else
    printf 'Need rsvg-convert or inkscape to rasterize the banner SVG.\n' >&2
    printf 'Install one first: pacman -S librsvg   (or)   pacman -S inkscape\n' >&2
    exit 1
fi

FONT=""
for candidate in \
    "/usr/share/fonts/TTF/JetBrainsMonoNerdFontMono-Bold.ttf" \
    "/usr/share/fonts/TTF/JetBrainsMono-Bold.ttf" \
    "/usr/share/fonts/TTF/DejaVuSansMono-Bold.ttf" \
    "/usr/share/fonts/TTF/DejaVuSansMono.ttf"; do
    if [[ -f "$candidate" ]]; then
        FONT="$candidate"
        break
    fi
done

if [[ -z "$FONT" ]]; then
    FONT="$(fc-match -f '%{file}' 'monospace:bold' 2>/dev/null || true)"
fi

if [[ -z "$FONT" || ! -f "$FONT" ]]; then
    printf 'Could not find a usable font file for ffmpeg drawtext.\n' >&2
    printf 'Install one: pacman -S ttf-jetbrains-mono-nerd   (or any monospace TTF)\n' >&2
    exit 1
fi

printf 'Using font: %s\n' "$FONT" >&2

RAW_W="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$RAW")"
RAW_H="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$RAW")"
RAW_FPS_RAT="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$RAW")"
RAW_FPS="$(awk -F/ '{ if ($2=="" || $2==0) print $1; else printf "%.0f", $1/$2 }' <<< "$RAW_FPS_RAT")"

printf 'Raw recording: %sx%s @ %sfps\n' "$RAW_W" "$RAW_H" "$RAW_FPS" >&2

BANNER_PNG="$WORK_DIR/banner.png"
"${SVG_RENDER[@]}" "$BANNER_PNG" "$BANNER_SVG"

LOGO_W=$((RAW_W * 55 / 100))
OPEN_CARD="$WORK_DIR/open.mp4"
CLOSE_CARD="$WORK_DIR/close.mp4"
CAPTIONED_RAW="$WORK_DIR/captioned.mp4"

ffmpeg -y -loglevel error \
    -f lavfi -i "color=c=0x05070a:s=${RAW_W}x${RAW_H}:d=3:r=${RAW_FPS}" \
    -i "$BANNER_PNG" \
    -filter_complex "[1:v]scale=${LOGO_W}:-1[logo];[0:v][logo]overlay=(W-w)/2:(H-h)/2[out]" \
    -map "[out]" -c:v libx264 -pix_fmt yuv420p "$OPEN_CARD"

URL_SIZE=$((RAW_H * 24 / 1080))
LIC_SIZE=$((RAW_H * 18 / 1080))
[[ "$URL_SIZE" -lt 14 ]] && URL_SIZE=14
[[ "$LIC_SIZE" -lt 12 ]] && LIC_SIZE=12

ffmpeg -y -loglevel error \
    -f lavfi -i "color=c=0x05070a:s=${RAW_W}x${RAW_H}:d=3:r=${RAW_FPS}" \
    -i "$BANNER_PNG" \
    -filter_complex "[1:v]scale=${LOGO_W}:-1[logo];[0:v][logo]overlay=(W-w)/2:(H*0.34-h/2)[bg];[bg]drawtext=fontfile=${FONT}:text='github.com/T-Crypt/Aphotic-Hypr':fontcolor=0x5eead4:fontsize=${URL_SIZE}:x=(w-text_w)/2:y=h*0.66[bg2];[bg2]drawtext=fontfile=${FONT}:text='GPL-3.0':fontcolor=0x5b7280:fontsize=${LIC_SIZE}:x=(w-text_w)/2:y=h*0.73[out]" \
    -map "[out]" -c:v libx264 -pix_fmt yuv420p "$CLOSE_CARD"

escape_dt() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//:/\\:}"
    s="${s//\'/\\\'}"
    s="${s//,/\\,}"
    printf '%s' "$s"
}

CAPTIONS=(
    "0|4|Desktop, at rest|HackTheBox theme active, full bar, nothing running"
    "4|16|Live theme switching|No rebuild, no relogin -- wallpaper and palette update instantly"
    "16|40|Bar hover popouts|Hover any status icon for a full detail panel"
    "40|60|One launcher, five modes|Apps, clipboard, emoji, windows, wallpapers, projects -- one search box"
    "60|68|Screenshot picker|Drag-select with live window snapping, plus a freeze-mode variant"
    "68|78|Notifications & OSD|Toast popups, on-screen volume and brightness feedback"
    "78|95|Command Center|Dashboard, performance, workspaces, wallpapers, and AI chat, one overlay"
    "95|128|Settings Control Center|Every category lives in one searchable, full-screen panel"
    "128|140|Plugin system|Browse the remote index, install OpenRGB Sync in one click"
    "140|150|Lock screen & power menu|Real session-lock protocol, real PAM auth"
    "150|156|Terminal games|Snake, hangman, and number-guessing, built into the CLI"
)

LABEL_SIZE=$((RAW_H * 34 / 1080))
DESC_SIZE=$((RAW_H * 20 / 1080))
[[ "$LABEL_SIZE" -lt 20 ]] && LABEL_SIZE=20
[[ "$DESC_SIZE" -lt 13 ]] && DESC_SIZE=13
MARGIN_X=$((RAW_W * 5 / 100))
LABEL_Y=$((RAW_H - RAW_H * 14 / 100))
DESC_Y=$((RAW_H - RAW_H * 9 / 100))

FILTER=""
PREV="0:v"
INDEX=0
for row in "${CAPTIONS[@]}"; do
    IFS='|' read -r start end lbl desc <<< "$row"
    lbl_e="$(escape_dt "$lbl")"
    desc_e="$(escape_dt "$desc")"
    NEXT="cap${INDEX}"
    FILTER+="[${PREV}]drawtext=fontfile=${FONT}:text='${lbl_e}':fontcolor=0xe6edf3:fontsize=${LABEL_SIZE}:x=${MARGIN_X}:y=${LABEL_Y}:box=1:boxcolor=0x05070a@0.55:boxborderw=14:enable='between(t\,${start}\,${end})'[${NEXT}a];"
    FILTER+="[${NEXT}a]drawtext=fontfile=${FONT}:text='${desc_e}':fontcolor=0x9fb0bd:fontsize=${DESC_SIZE}:x=${MARGIN_X}:y=${DESC_Y}:box=1:boxcolor=0x05070a@0.55:boxborderw=10:enable='between(t\,${start}\,${end})'[${NEXT}];"
    PREV="$NEXT"
    INDEX=$((INDEX + 1))
done
FILTER="${FILTER%;}"

ffmpeg -y -loglevel error -i "$RAW" \
    -filter_complex "$FILTER" \
    -map "[${PREV}]" -c:v libx264 -pix_fmt yuv420p -r "$RAW_FPS" "$CAPTIONED_RAW"

CONCAT_LIST="$WORK_DIR/concat.txt"
{
    printf "file '%s'\n" "$OPEN_CARD"
    printf "file '%s'\n" "$CAPTIONED_RAW"
    printf "file '%s'\n" "$CLOSE_CARD"
} > "$CONCAT_LIST"

ffmpeg -y -loglevel error -f concat -safe 0 -i "$CONCAT_LIST" -c copy "$FINAL"

printf 'Assembled: %s\n' "$FINAL" >&2
