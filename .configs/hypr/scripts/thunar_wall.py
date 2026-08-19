import os
import argparse

ap = argparse.ArgumentParser()
ap.add_argument("-i", "--image", required=True, help="path to input image")
args = vars(ap.parse_args())

image_path = args["image"]

# Change the wallpaper
os.system(f'swww img -t wipe --transition-duration 3 {image_path}')
# Generate the wallust colorscheme; templates write straight to their targets (see wallust.toml)
os.system(f'wallust run {image_path}')
# generate wallpaper.rofi
os.system(f'cp {image_path} ~/.config/swww/wallpaper.rofi')
# firefox
os.system(f'pywalfox update')
# Reload waybar to apply colorscheme
os.system(f'killall -SIGUSR2 waybar')
# Send a notification
os.system(
    f'notify-send -h string:x-canonical-private-synchronous:hypr-cfg -u low "Wallpaper changed to {os.path.basename(image_path)}"')
