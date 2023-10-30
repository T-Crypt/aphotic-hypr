# Hyprland Dotfiles

**NOTE: Yay must be installed 

```
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
```


### Dependencies 

```
yay -S hyprland-bin kitty waybar-hyprland \
    swaybg swaylock-effects rofi sddm wlogout mako thunar \
    ttf-jetbrains-mono-nerd thunar-archive-plugin file-roller noto-fonts-emoji \
    polkit-gnome python-requests swww starship \
    swappy grim slurp pamixer brightnessctl gvfs \
    bluez bluez-utils neofetch lxappearance xfce4-settings \
    dracula-gtk-theme dracula-icons-git xdg-desktop-portal-hyprland-git
```

### 🐜 ScreenShots

![](./assets/swappy-20231030_113753.png)
![](./assets/swappy-20231030_122656.png)




### Changes to Make

You need to edit the wttr-in.py script to change city location

Current Location: Denver, CO

`.config/waybar/scripts/waybar-wttr.py`
