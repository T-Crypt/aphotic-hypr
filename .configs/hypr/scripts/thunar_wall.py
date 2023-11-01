import os
import argparse

ap = argparse.ArgumentParser()
ap.add_argument("-i", "--image", required=True, help="path to input image")
args = vars(ap.parse_args())

image_path = args["image"]

os.system(f'swww img -t wipe --transition-duration 3 {image_path}')
# Generarte Pywal colorscheme
os.system(f'wal -i {image_path}')
#generate wallpaper.rofi 
os.system(f'cp {image_path} ~/.config/swww/wallpaper.rofi')
os.system(f'cp ~/.cache/wal/colors-hyprland.conf ~/.config/hypr/colors-hyprland.conf') # hyprland
os.system(f'cp ~/.cache/wal/colors-waybar.css ~/.config/waybar/') # waybar
os.system(f'cp ~/.cache/wal/colors-kitty.conf ~/.config/kitty/') # kitty also needed to apply the colorscheme to all new windows after wallpaper change
os.system(f'cp ~/.cache/wal/colors-swaylock ~/.config/swaylock/config') # swaylock
os.system(f'cp ~/.cache/wal/colors-cava ~/.config/cava/config') # cava
os.system(f'cp ~/.cache/wal/colors-rofi.rasi ~/.config/rofi/colors/colors-rofi.rasi') # rofi
os.system(f'pywalfox update') # apply firefox theme
# Reload waybar to apply colorscheme
os.system(f'killall -SIGUSR2 waybar')
# Send a notification
os.system(f'notify-send -h string:x-canonical-private-synchronous:hypr-cfg -u low "Wallpaper changed to {image_path}"')
