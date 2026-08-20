#!/usr/bin/env bash
# Clipboard history picker, backed by cliphist.

selected=$(cliphist list | rofi -dmenu -theme "$HOME/.config/rofi/style.rasi" -p "Clipboard")
[[ -n "$selected" ]] || exit 0

echo "$selected" | cliphist decode | wl-copy
