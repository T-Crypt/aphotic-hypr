import os
import argparse

ap = argparse.ArgumentParser()
ap.add_argument("-i", "--image", required=True, help="path to input image")
args = vars(ap.parse_args())

image_path = args["image"]

    # Change the wallpaper
    os.system(f'swww img -t wipe --transition-duration 3 {image_path}')
    # Generarte Pywal colorscheme
    os.system(f'wal -i {image_path}')
    #generate wallpaper.rofi 
    os.system(f'cp {image_path} ~/.config/swww/wallpaper.rofi')
    # cava
    os.system(f'cp ~/.cache/wal/colors-cava ~/.config/cava/config')  
    # hyprland
    os.system(f'cp ~/.cache/wal/colors-hyprland.conf ~/.config/hypr/colors-hyprland.conf')
    # waybar
    os.system(f'cp ~/.cache/wal/colors-waybar.css ~/.config/waybar/')  
    # kitty 
    os.system(f'cp ~/.cache/wal/colors-kitty.conf ~/.config/kitty/')
    # swaylock
    os.system(f'cp ~/.cache/wal/colors-swaylock ~/.config/swaylock/config')
    # mako
    os.system(f'cp ~/.cache/wal/colors-mako ~/.config/mako/config')
     # rofi 
    os.system(f'cp ~/.cache/wal/colors-rofi.rasi ~/.config/rofi/colors/colors-rofi.rasi')  
     # firefox
    os.system(f'pywalfox update')
    # Reload waybar to apply colorscheme
    os.system(f'killall -SIGUSR2 waybar') 
    # Send a notification
    os.system(f'notify-send -h string:x-canonical-private-synchronous:hypr-cfg -u low "Wallpaper changed to {random_image}"')
