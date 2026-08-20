#!/bin/bash

# Fetch the current wallpaper path from awww's JSON query output.
# Format: {"NAMESPACE": [{"name":..., "displaying": {"image": "<path>"}}]}
IMAGE_PATH=$(awww query -j | python3 -c '
import json, sys
data = json.load(sys.stdin)
for outputs in data.values():
    for output in outputs:
        image = output.get("displaying", {}).get("image")
        if image:
            print(image)
            sys.exit(0)
')

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
