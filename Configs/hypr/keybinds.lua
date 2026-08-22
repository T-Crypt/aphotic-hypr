-- Keybindings — see https://wiki.hypr.land/Configuring/Basics/Binds/

local mainMod = "SUPER"

-- Main binds
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("kitty"))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("qs -c aphotic ipc call lock engage"))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("wlogout --protocol layer-shell"))
hl.bind(mainMod .. " + backspace", hl.dsp.exec_cmd("qs -c aphotic ipc call session toggle"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("thunar"))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("qs -c aphotic ipc call launcher toggle"))
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd("qs -c aphotic ipc call launcher toggle"))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd('grim -g "$(slurp)" - | swappy -f -'))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("python3 ~/.config/hypr/scripts/wallswitcher.py"))
hl.bind(mainMod .. " + CTRL + W", hl.dsp.exec_cmd("qs -c aphotic ipc call launcher openWallpapers"))
hl.bind(mainMod .. " + comma", hl.dsp.exec_cmd("aphotic theme prev"))
hl.bind(mainMod .. " + period", hl.dsp.exec_cmd("aphotic theme next"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("systemctl --user restart aphotic-shell.service"))
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd("firefox"))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("code"))

-- Quickshell surfaces (Command Center, Settings, notifications)
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("qs -c aphotic ipc call dashboard toggle"))
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("qs -c aphotic ipc call settings toggle"))
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd("qs -c aphotic ipc call notifs clear"))

-- Quickshell area picker (drag-select with client snapping + freeze preview) —
-- distinct from the raw grim/slurp/swappy bind on mainMod + S above, which
-- stays as the simple no-frills fallback.
hl.bind(mainMod .. " + SHIFT + S",         hl.dsp.exec_cmd("qs -c aphotic ipc call picker open"))
hl.bind(mainMod .. " + CTRL + S",          hl.dsp.exec_cmd("qs -c aphotic ipc call picker openFreeze"))
hl.bind(mainMod .. " + ALT + S",           hl.dsp.exec_cmd("qs -c aphotic ipc call picker openClip"))
hl.bind(mainMod .. " + CTRL + ALT + S",    hl.dsp.exec_cmd("qs -c aphotic ipc call picker openFreezeClip"))

-- Audio output cycling and special-workspace cycling (Quickshell IPC, no
-- other UI path exists for either of these yet)
hl.bind(mainMod .. " + CTRL + O", hl.dsp.exec_cmd("qs -c aphotic ipc call audio cycleOutput"))
hl.bind(mainMod .. " + CTRL + Tab",         hl.dsp.exec_cmd("qs -c aphotic ipc call hypr cycleSpecialWorkspace next"))
hl.bind(mainMod .. " + CTRL + SHIFT + Tab", hl.dsp.exec_cmd("qs -c aphotic ipc call hypr cycleSpecialWorkspace prev"))

-- Window binds
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + G", hl.dsp.group.toggle())
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + ALT + Q", hl.dsp.window.kill())
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + CTRL + F", hl.dsp.window.pin())

-- Group navigation
hl.bind(mainMod .. " + CTRL + H", hl.dsp.group.prev())
hl.bind(mainMod .. " + CTRL + L", hl.dsp.group.next())

-- Alt-tab window switcher
hl.bind("ALT + Tab",         hl.dsp.window.cycle_next())
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false }))

-- Media keys (mpris — Quickshell's own player service, works with any
-- MPRIS-capable player, not just one hardcoded to a specific app)
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("qs -c aphotic ipc call mpris playPause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("qs -c aphotic ipc call mpris playPause"), { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("qs -c aphotic ipc call mpris next"),      { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("qs -c aphotic ipc call mpris previous"),  { locked = true })

-- Laptop binds
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("pamixer -t"),                     { locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("pamixer -d 5"),                   { locked = true, repeating = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("pamixer -i 5"),                   { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("pamixer --default-source -t"),    { locked = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl set 10%-"),         { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl set 10%+"),         { locked = true, repeating = true })

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Move (swap) the active window with mainMod + SHIFT + arrow keys
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Jump to the nearest empty workspace
hl.bind(mainMod .. " + CTRL + down", hl.dsp.focus({ workspace = "empty" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
