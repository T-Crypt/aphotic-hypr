#!/usr/bin/env bash
# Wallpaper picker: choose an image from ~/.config/awww, apply it, and
# regenerate the wallust palette — the deliberate-choice counterpart to
# wallswitcher.py's random switch.

WALLPAPER_DIR="$HOME/.config/awww"

selected=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' \) -printf '%f\n' \
  | rofi -dmenu -theme "$HOME/.config/rofi/style.rasi" -p "Wallpaper")
[[ -n "$selected" ]] || exit 0

image_path="$WALLPAPER_DIR/$selected"

awww img --transition-type wipe --transition-duration 3 "$image_path"
wallust run "$image_path"
cp "$image_path" "$WALLPAPER_DIR/wallpaper.rofi"
pywalfox update
noctis reload
notify-send -h string:x-canonical-private-synchronous:hypr-cfg -u low "Wallpaper changed to $selected"
