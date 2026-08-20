#!/usr/bin/env python

import os
import random

# full path to your wallpaper folder
wallpath = os.path.expanduser("~/.config/awww")


def change_wallpaper(folder_path):
    # Get a list of image files in the specified folder
    image_files = [f for f in os.listdir(folder_path) if f.lower().endswith(
        ('.png', '.jpg', '.jpeg', '.gif'))]

    if not image_files:
        os.system(
            f'notify-send -h string:x-canonical-private-synchronous:hypr-cfg -u low "No image files found in the folder"')
        return

    # Choose a random image from the list
    random_image = random.choice(image_files)
    image_path = os.path.join(folder_path, random_image)

    # Change the wallpaper
    os.system(f'awww img --transition-type wipe --transition-duration 3 {image_path}')
    # Generate the wallust colorscheme; templates write straight to their targets (see wallust.toml)
    os.system(f'wallust run {image_path}')
    # generate wallpaper.rofi
    os.system(f'cp {image_path} ~/.config/awww/wallpaper.rofi')
    # firefox
    os.system(f'pywalfox update')
    # Reload waybar to apply colorscheme
    os.system(f'killall -SIGUSR2 waybar')
    # Send a notification
    os.system(
        f'notify-send -h string:x-canonical-private-synchronous:hypr-cfg -u low "Wallpaper changed to {random_image}"')


if __name__ == "__main__":
    folder_path = wallpath
    change_wallpaper(folder_path)
