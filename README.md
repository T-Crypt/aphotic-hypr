#  Hyprland Dotfiles

<p align="center">
  <img src="https://img.shields.io/github/stars/T-Crypt/dots?style=for-the-badge&color=7DCFFF">
  <img src="https://img.shields.io/github/issues/T-Crypt/dots?&style=for-the-badge&color=E0AF68">
  <img src="https://img.shields.io/github/forks/T-Crypt/dots?&style=for-the-badge&color=F7768E">
  <img alt="GitHub last commit (by committer)" src="https://img.shields.io/github/last-commit/T-Crypt/dots?style=for-the-badge&color=AD8EE6">
  </p>


**NOTE: Yay must be installed 

```
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
```


### 🗄️ Dependencies 

```
yay -S hyprland-bin kitty waybar-hyprland \
    swaybg swaylock-effects rofi sddm-git wlogout mako thunar \
    ttf-jetbrains-mono-nerd thunar-archive-plugin file-roller noto-fonts-emoji \
    polkit-gnome python-requests swww starship \
    swappy grim slurp pamixer brightnessctl gvfs \
    bluez bluez-utils neofetch lxappearance xfce4-settings \
    dracula-gtk-theme dracula-icons-git xdg-desktop-portal-hyprland-git \
    python python-pyamdgpuinfo jq 
```

### 💻 Install

```
git clone https://github.com/T-Crypt/dots && cd dots
cp -R .config/* ~/.config/
sudo systemctl enable sddm.service
sudo systemctl start sddm.service
```

<details> 
  <summary><h2>🏷️ Additional Packages </h2></summary>

</details>



### 🐜 ScreenShots

![](./assets/swappy-20231030_113753.png)

![](./assets/swappy-20231030_122656.png)

![](./assets/swappy-20231030_123719.png)

![](./assets/swappy-20231030_123804.png)


### Changes to Make

You need to edit the wttr-in.py script to change city location

Current Location: Denver, CO

`.config/waybar/scripts/waybar-wttr.py`
