import os
import random

# full path to your wallpaper folder
wallpath = r"/home/rokno/Pictures/Wallpapers"


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
    os.system(f'swww img -t wipe --transition-duration 3 {image_path}')
    # Generarte Pywal colorscheme
    os.system(f'wal -i {image_path}')
    # Make a hard copy of the colorscheme
    os.system(f'cp ~/.cache/wal/colors-dunst ~/.config/dunst/dunstrc')  # dunst
    # hyprland
    os.system(f'cp ~/.cache/wal/colors-hyprland.conf ~/.config/hypr/colors-hyprland.conf')
    # restart dunst to apply new theme
    os.system(f'killall dunst && dunst & disown')
    os.system(f'cp ~/.cache/wal/colors-waybar.css ~/.config/waybar/')  # waybar
    # kitty also needed to apply the colorscheme to all new windows after wallpaper change
    os.system(f'cp ~/.cache/wal/colors-kitty.conf ~/.config/kitty/')
    # wlogout
    os.system(
        f'cp ~/.cache/wal/colors-waybar.css ~/.config/wlogout/color-wlogout.css')
    # swaylock
    os.system(f'cp ~/.cache/wal/colors-swaylock ~/.config/swaylock/config')
    os.system(f'cp ~/.cache/wal/colors-cava ~/.config/cava/config')  # cava
    os.system(
        f'cp ~/.cache/wal/colors-rofi.rasi ~/.config/rofi/colors/colors-rofi.rasi')  # rofi
    # spotify
    os.system(
        f'cp ~/.cache/wal/colors-spicetify.ini ~/.config/spicetify/Themes/wal/color.ini')
    os.system(f'spicetify apply')  # apply spotify theme
    os.system(
        f'cp ~/.cache/wal/colors-btop.theme ~/.config/btop/themes/wal.theme')  # btop
    os.system(f'pywalfox update')  # firefox
    # Reload waybar to apply colorscheme
    os.system(f'killall -SIGUSR2 waybar')  # reload waybar to update theme
    # Send a notification
    os.system(
        f'notify-send -h string:x-canonical-private-synchronous:hypr-cfg -u low "Wallpaper changed to {random_image}"')


if __name__ == "__main__":
    folder_path = wallpath
    change_wallpaper(folder_path)
