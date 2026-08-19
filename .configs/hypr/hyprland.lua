-- Noctis — Hyprland config entry point
-- See https://wiki.hypr.land/Configuring/Start/

require("monitors")
require("keybinds")
require("windows")
require("startup")
require("theme")

local ok, colors = pcall(require, "colors")
if not ok then
    -- No wallpaper picked yet — wallust writes ~/.config/hypr/colors.lua
    -- on first run (see wallswitcher.py / thunar_wall.py).
    colors = {
        background = "#0c0a14",
        foreground = "#8ddae9",
        color0 = "#0c0a14", color1 = "#5D59A9", color2 = "#A366B1", color3 = "#CF75B8",
        color4 = "#E478BA", color5 = "#AB44CB", color6 = "#DC57D3", color7 = "#8ddae9",
        color8 = "#6298a3", color9 = "#5D59A9", color10 = "#A366B1", color11 = "#CF75B8",
        color12 = "#E478BA", color13 = "#AB44CB", color14 = "#DC57D3",
    }
end

hl.config({
    general = {
        gaps_in  = 3,
        gaps_out = 8,
        border_size = 2,

        col = {
            active_border   = { colors = { colors.color3, colors.color11, colors.color14 } },
            inactive_border = "rgba(595959aa)",
        },

        layout = "dwindle",
        resize_on_border = true,
    },

    misc = {
        disable_hyprland_logo = true,
        background_color = colors.background,
    },

    decoration = {
        rounding = 10,

        active_opacity   = 0.70,
        inactive_opacity = 0.70,

        blur = {
            enabled = true,
            size = 2,
            passes = 3,
            new_optimizations = true,
            ignore_opacity = true,
        },

        dim_inactive = false,
        dim_strength = 0.2,
        dim_around   = 0.4,

        shadow = {
            enabled      = true,
            ignore_window = true,
            offset       = { 1, 2 },
            range        = 10,
            render_power = 2,
            color        = 0x66000000,
        },
    },

    group = {
        col = {
            border_active          = colors.color4,
            border_inactive        = colors.color3,
            border_locked_active   = colors.color4,
            border_locked_inactive = colors.color3,
        },
    },

    dwindle = {
        pseudotile = true,
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,
        sensitivity  = 0,

        touchpad = {
            natural_scroll = false,
        },
    },

    animations = {
        enabled = true,
    },
})

hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

-- Animation curves and timings
hl.curve("wind",   { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
hl.curve("winIn",  { type = "bezier", points = { {0.1, 1.1},  {0.1, 1.1}  } })
hl.curve("winOut", { type = "bezier", points = { {0.3, -0.3}, {0, 1}      } })
hl.curve("liner",  { type = "bezier", points = { {1, 1},      {1, 1}      } })

hl.animation({ leaf = "windows",     enabled = true, speed = 6,  bezier = "wind",   style = "slide" })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 6,  bezier = "winIn",  style = "slide" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 5,  bezier = "winOut", style = "slide" })
hl.animation({ leaf = "border",      enabled = true, speed = 1,  bezier = "liner" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 30, bezier = "liner", style = "loop" })
hl.animation({ leaf = "fade",        enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 5,  bezier = "wind" })

-- install.sh appends `require("nvidia")` below this line when an Nvidia GPU is detected.
