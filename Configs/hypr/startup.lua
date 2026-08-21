-- Autostart — see https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function()
    hl.exec_cmd("~/.config/hypr/xdg-portal-hyprland")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    -- Started as a systemd --user unit (Configs/systemd/user/noctis-shell.service)
    -- rather than a bare exec: gives the shell real Restart=on-failure
    -- supervision instead of silently staying dead if it crashes, which
    -- happened at least once with nothing surfacing the fact. `systemctl
    -- --user restart` is also how the SUPER+B keybind now recovers it
    -- (see keybinds.lua), so start/restart go through the same path.
    hl.exec_cmd("systemctl --user start noctis-shell.service")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("sleep 1 && awww-daemon")

    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Ice 20")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Ice'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size 20")

    -- Papirus, not Dracula: papirus-folders can swap its folder icons
    -- between ~16 preset colors to roughly match each theme's accent
    -- (see cmd_theme.sh's _noctis_theme_apply) -- real per-icon
    -- recoloring isn't possible with a fixed-palette icon theme like
    -- Dracula, since each icon's colors are baked into its own file.
    hl.exec_cmd("gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'")
    -- gtk-theme is adw-gtk3-dark, not Dracula or GTK's own bundled
    -- Adwaita-dark: Dracula hardcodes its palette outright, and GTK3's
    -- own built-in Adwaita compiles its headerbar/window chrome from
    -- SCSS with baked-in colors that ignore user @define-color overrides
    -- for anything but a few minor roles (verified live: a gtk.css
    -- override took effect on list-selection highlights but not window/
    -- headerbar backgrounds under plain Adwaita-dark). adw-gtk-theme is a
    -- separate package that reimplements the same look purely through
    -- those overridable named tokens -- the theme actually built for
    -- pywal/wallust-style dynamic recoloring, which is why wallust's
    -- gtk.css override (Configs/wallust/templates/gtk.css) only takes
    -- real effect with it installed and selected.
    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")

    hl.exec_cmd("gsettings set org.gnome.desktop.interface font-name 'Cantarell 10'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface document-font-name 'Cantarell 10'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface monospace-font-name 'CaskaydiaCove Nerd Font Mono 9'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface font-hinting 'full'")
end)
