#!/bin/bash

# Define the software packages to install
packages=(
    "qt5-wayland"
    "qt5ct"
    "qt6-wayland"
    "qt6ct"
    "qt5-svg"
    "qt5-quickcontrols2"
    "qt5-graphicaleffects"
    "gtk3"
    "polkit-gnome"
    "pipewire"
    "wireplumber"
    "jq"
    "wl-clipboard"
    "cliphist"
    "python-requests"
    "pacman-contrib"
    "kitty"
    "mako"
    "waybar"
    "swww"
    "swaylock-effects"
    "wofi"
    "wlogout"
    "xdg-desktop-portal-hyprland"
    "swappy"
    "grim"
    "slurp"
    "thunar"
    "btop"
    "firefox"
    "thunderbird"
    "mpv"
    "pamixer"
    "pavucontrol"
    "brightnessctl"
    "bluez"
    "bluez-utils"
    "blueman"
    "network-manager-applet"
    "gvfs"
    "thunar-archive-plugin"
    "file-roller"
    "starship"
    "papirus-icon-theme"
    "ttf-jetbrains-mono-nerd"
    "noto-fonts-emoji"
    "lxappearance"
    "xfce4-settings"
    "nwg-look-bin"
    "sddm"
)

# Check if a package is installed, and if not, install it
install_package() {
    local package="$1"
    if yay -Q "$package" &>/dev/null; then
        echo "[OK] $package is already installed."
    else
        echo "[Installing] $package..."
        if yay -S --noconfirm "$package"; then
            echo "[OK] $package installed successfully."
        else
            echo "[Error] Failed to install $package."
            exit 1
        fi
    fi
}

# Check if a program is running and show a progress bar
show_progress() {
    local pid="$1"
    while ps | grep "$pid" &>/dev/null; do
        echo -n "."
        sleep 2
    done
    echo " Done!"
}

# Check if the system has an NVIDIA GPU
check_nvidia_gpu() {
    if lspci -k | grep -A 2 -E "(VGA|3D)" | grep -iq nvidia; then
        echo "[Info] NVIDIA GPU found."
        return 0
    else
        echo "[Info] No NVIDIA GPU detected."
        return 1
    fi
}

# Function to handle user confirmation
confirm_action() {
    read -rp "$1 (y/n): " choice
    case "$choice" in
    [Yy]) return 0 ;;
    [Nn]) return 1 ;;
    *) return 1 ;;
    esac
}

# Set up networking and system configuration
configure_system() {
    echo "[Info] Configuring system..."
    # Add your system configuration here
}

# Main script starts here

clear

echo "[Note] You are about to execute a script to set up Hyprland."
echo "[Note] Hyprland is still in Beta."
sleep 1

if confirm_action "[Action] Check for Physical or VM"; then
    ISVM=$(hostnamectl | grep Chassis)
    echo "Using $ISVM"
    if [[ $ISVM == *"vm"* ]]; then
        echo "[Warning] Please note that VMs are not fully supported, and this script might fail."
        sleep 1
    fi
fi

if confirm_action "[Action] Continue with the installation"; then
    echo "[Info] Setup starting..."
    sudo touch /tmp/hyprv.tmp
else
    echo "[Info] This script will exit without making any changes to your system."
    exit
fi

if confirm_action "[Action] Disable WiFi powersave"; then
    LOC="/etc/NetworkManager/conf.d/wifi-powersave.conf"
    echo -e "[connection]\nwifi.powersave = 2" | sudo tee -a "$LOC"
    echo "[Info] Restarting NetworkManager service..."
    sudo systemctl restart NetworkManager
    sleep 2
    echo "[OK] NetworkManager restart completed."
fi

if confirm_action "[Action] Configure yay package manager"; then
    if [ ! -f /sbin/yay ]; then
        echo "[Info] Configuring yay..."
        git clone https://aur.archlinux.org/yay.git
        cd yay
        makepkg -si --noconfirm
        cd ..
        echo "[Info] yay configured."
        echo "[Info] Updating yay database..."
        yay -Suy --noconfirm
        echo "[OK] yay updated."
    fi
fi

if confirm_action "[Action] Install software packages"; then
    echo "[Info] Installing software packages, this may take a while..."
    for package in "${packages[@]}"; do
        install_package "$package"
    done

    if check_nvidia_gpu; then
        echo "[Info] Nvidia GPU support setup stage, this may take a while..."
        # Add packages specific to NVIDIA GPU here
    fi

    echo "[Info] Installing Hyprland, this may take a while..."
    # Install Hyprland or Hyprland with NVIDIA support as needed

    echo "[Info] Installing main components, this may take a while..."
    # Install main components
fi

if confirm_action "[Action] Copy config files"; then
    echo "[Info] Copying config files..."
    # Copy and set up configuration files
fi

if confirm_action "[Action] Activate the starship shell"; then
    echo "[Info] Activating the starship shell..."
    # Install and configure the starship shell
fi

if confirm_action "[Action] Install ASUS ROG laptop support"; then
    echo "[Info] Installing ASUS ROG laptop support..."
    # Install ASUS ROG laptop support packages and configure them
fi

echo "[Info] Script completed!"
if check_nvidia_gpu; then
    echo "[Attention] Since an NVIDIA GPU setup was attempted, please reboot your system."
    echo "[Attention] Type 'reboot' at the prompt and press Enter when ready."
fi

read -n1 -rep 'Would you like to start Hyprland now? (y,n)' HYP
if [[ $HYP == "Y" || $HYP == "y" ]]; then
    exec Hyprland
else
    exit
fi
