-- Compositor for the login greeter: no gaps, borders or animations. When the
-- greeter exits, so does this compositor, and greetd starts the session.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1.0,
})

hl.config({
    general = {
        gaps_in = 0,
        gaps_out = 0,
        border_size = 0,
    },
    decoration = {
        rounding = 0,
        blur = {
            enabled = false,
        },
    },
    animations = {
        enabled = false,
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },
})

hl.on("hyprland.start", function()
    hl.exec_cmd("sh -c 'qs -c aphotic-greeter; hyprctl dispatch exit'")
end)
