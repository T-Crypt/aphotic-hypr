#!/usr/bin/env bash
# Emoji picker: select from the curated list, copy the emoji to clipboard.

selected=$(rofi -dmenu -theme "$HOME/.config/rofi/style.rasi" -p "Emoji" -i < "$HOME/.config/rofi/emoji.txt")
[[ -n "$selected" ]] || exit 0

echo -n "${selected%% *}" | wl-copy
