#!/bin/bash

# Directory containing wallpapers
WALLPAPER_DIR="$HOME/.config/swww/"

# File to store the current wallpaper path
CURRENT_WALLPAPER_FILE="$WALLPAPER_DIR/wallpaper.rofi"

# Get a list of image files in the directory
WALLPAPERS=("$WALLPAPER_DIR"/*.jpg "$WALLPAPER_DIR"/*.png)

# Find the index of the next wallpaper in the array
NEXT_INDEX=$(($(($RANDOM % ${#WALLPAPERS[@]})) - 1))

# Set the next wallpaper using swww img with the full path
swww img "${WALLPAPERS[$NEXT_INDEX]}" --transition-type wipe --transition-angle 30 --transition-step 90

# Copy the currently set wallpaper to current_wallpaper.rofi
cp "${WALLPAPERS[$NEXT_INDEX]}" "$CURRENT_WALLPAPER_FILE"

echo "Wallpaper changed to: ${WALLPAPERS[$NEXT_INDEX]}"
