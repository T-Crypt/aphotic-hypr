#!/bin/bash

sleep 1; swww init

# Directory containing wallpapers
WALLPAPER_DIR="$HOME/.config/swww/"

# Temporary file to store the last set wallpaper
LAST_WALLPAPER_FILE="$HOME/.config/swww/last_wallpaper.txt"

# Check if the wallpaper directory exists
if [ ! -d "$WALLPAPER_DIR" ]; then
    echo "Error: Wallpaper directory not found."
    exit 1
fi

# Get the currently displayed wallpaper using swww query
CURRENT_WALLPAPER=$(swww query | awk -F ': ' '/currently displaying/ {print $2}')

# Get the last set wallpaper from the temporary file
LAST_WALLPAPER=$(cat "$LAST_WALLPAPER_FILE")

# Get a list of image files in the directory
WALLPAPERS=("$WALLPAPER_DIR"/*.jpg "$WALLPAPER_DIR"/*.png)

# Find the index of the current wallpaper in the array
CURRENT_INDEX=-1
for i in "${!WALLPAPERS[@]}"; do
    if [[ "${WALLPAPERS[$i]}" == "$LAST_WALLPAPER" ]]; then
        CURRENT_INDEX=$i
        break
    fi
done

# If last set wallpaper is not found, set the first wallpaper
if [ "$CURRENT_INDEX" == "-1" ]; then
    CURRENT_INDEX=0
fi

# Calculate the index of the next wallpaper
NEXT_INDEX=$(( (CURRENT_INDEX + 1) % ${#WALLPAPERS[@]} ))

# Set the next wallpaper using swww img with the full path
swww img "${WALLPAPERS[$NEXT_INDEX]}"

# Save the new wallpaper to the temporary file
echo "${WALLPAPERS[$NEXT_INDEX]}" > "$LAST_WALLPAPER_FILE"

echo "Wallpaper changed to: ${WALLPAPERS[$NEXT_INDEX]}"
