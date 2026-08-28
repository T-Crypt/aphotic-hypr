-- Autostart — see https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function()
    hl.exec_cmd("~/.config/hypr/xdg-portal-hyprland")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    -- Started as a systemd --user unit (Configs/systemd/user/aphotic-shell.service)
    -- rather than a bare exec: gives the shell real Restart=on-failure
    -- supervision instead of silently staying dead if it crashes, which
    -- happened at least once with nothing surfacing the fact. `systemctl
    -- --user restart` is also how the SUPER+B keybind now recovers it
    -- (see keybinds.lua), so start/restart go through the same path.
    hl.exec_cmd("systemctl --user start aphotic-shell.service")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("sleep 1 && awww-daemon")
    -- Connects only if Settings.vpnAutoConnect is true (checked inside
    -- the command itself, see cmd_vpn.sh's `autostart` subcommand) --
    -- warns and no-ops without passwordless sudo, same as everything
    -- else in commands/README.md's sudoers section.
    hl.exec_cmd("aphotic vpn autostart")

    -- Cursor theme/size, icon theme, and gtk-theme used to be hardcoded
    -- here, but that meant every reboot silently overwrote whatever was
    -- picked in Settings' Personalization pane (or, for gtk-theme, drifted
    -- and just stayed drifted -- nothing reasserted it between Hyprland
    -- restarts). services/Settings.qml now applies all three itself
    -- (hyprctl setcursor + gsettings) right after loading its persisted
    -- state, whether that's a user choice or the same defaults that used
    -- to live here -- single source of truth instead of two places
    -- fighting over it. See Settings.qml's `gtkTheme` property/
    -- `_applyGtkTheme()` for why adw-gtk3-dark specifically.
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")

    hl.exec_cmd("gsettings set org.gnome.desktop.interface font-name 'Cantarell 10'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface document-font-name 'Cantarell 10'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface monospace-font-name 'CaskaydiaCove Nerd Font Mono 9'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface font-hinting 'full'")
end)
