#!/bin/bash

# Fetch the current wallpaper information using awww query
# NOTE: awww's query output format is not fully documented upstream —
# if this doesn't find the wallpaper, run `awww query` manually and
# adjust the awk pattern below to match its actual output.
WALLPAPER_INFO=$(awww query)

# Extract the image path from the awww query output using awk
IMAGE_PATH=$(echo "$WALLPAPER_INFO" | awk -F ": image: " '{print $2}' | sort | uniq | head -n 1)

# Check if the image path is not empty
if [ -n "$IMAGE_PATH" ]; then
    # Extract the image filename without the path
    IMAGE_FILENAME=$(basename "$IMAGE_PATH")

    # Copy the image to the SDDM backgrounds directory
    sudo cp "$IMAGE_PATH" /usr/share/sddm/themes/sugar-candy/Backgrounds/

    # Update the theme.conf file with the new background image path
    sudo sed -i "/^Background=/s|.*$|Background=\"Backgrounds/$IMAGE_FILENAME\"|" /usr/share/sddm/themes/sugar-candy/theme.conf

    echo "Current wallpaper copied to SDDM backgrounds directory."
    echo "Updated Sugar-Candy with the new background image."
else
    echo "Error: Unable to fetch current wallpaper information using awww query."
fi
