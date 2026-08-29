-- Keybindings — see https://wiki.hypr.land/Configuring/Basics/Binds/

local mainMod = "SUPER"

-- Main binds
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("kitty"), { description = "Open terminal" })
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("qs -c aphotic ipc call lock engage"), { description = "Lock screen" })
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("wlogout --protocol layer-shell"), { description = "Open power/logout menu" })
hl.bind(mainMod .. " + backspace", hl.dsp.exec_cmd("qs -c aphotic ipc call session toggle"), { description = "Toggle session menu" })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("thunar"), { description = "Open file manager" })
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("qs -c aphotic ipc call launcher toggle"), { description = "Toggle app launcher" })
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd("qs -c aphotic ipc call launcher toggle"), { description = "Toggle app launcher" })
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd('grim -g "$(slurp)" - | swappy -f -'), { description = "Screenshot: select area" })
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("qs -c aphotic ipc call wallpaperpicker toggle"), { description = "Wallpaper picker (current theme)" })
hl.bind(mainMod .. " + CTRL + W", hl.dsp.exec_cmd("qs -c aphotic ipc call launcher openWallpapers"), { description = "Browse wallpapers (all themes)" })
hl.bind(mainMod .. " + comma", hl.dsp.exec_cmd("aphotic theme prev"), { description = "Previous theme" })
hl.bind(mainMod .. " + period", hl.dsp.exec_cmd("aphotic theme next"), { description = "Next theme" })
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("systemctl --user restart aphotic-shell.service"), { description = "Restart Aphotic shell" })
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd("firefox"), { description = "Open Firefox" })
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("code"), { description = "Open VS Code" })

-- Quickshell surfaces (Command Center, Settings, notifications)
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("qs -c aphotic ipc call dashboard toggle"), { description = "Toggle Command Center" })
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("qs -c aphotic ipc call settings toggle"), { description = "Toggle Settings" })
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd("qs -c aphotic ipc call notifs clear"), { description = "Clear all notifications" })
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("qs -c aphotic ipc call notifications toggle"), { description = "Toggle Notification Center" })
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("qs -c aphotic ipc call aphotic toggle keybindscheatsheet"), { description = "Toggle keybinds cheatsheet" })
-- AUR/official package search + install (Arch-only; silently a no-op if
-- neither yay nor paru is on PATH, see services/PkgSearch.qml)
hl.bind(mainMod .. " + Y", hl.dsp.exec_cmd("qs -c aphotic ipc call pkginstall toggle"), { description = "Toggle package search/install" })
hl.bind(mainMod .. " + SHIFT + D", hl.dsp.exec_cmd("qs -c aphotic ipc call dnd toggle"), { description = "Toggle Do Not Disturb" })

-- Cycle bar style (full -> dock -> taskbar -> minimal -> ...), same
-- entry point as the Settings -> Bar tab and `aphotic bar cycle`
hl.bind(mainMod .. " + CTRL + SHIFT + B", hl.dsp.exec_cmd("qs -c aphotic ipc call bar cycleStyle"), { description = "Cycle bar style" })

-- Intelligence quick-chat popout -- a fast, always-ready inference overlay
-- distinct from the Command Center's AI Chat tab (SUPER+D), with its own
-- persisted session history. SHIFT+A rather than plain A since mainMod+A
-- is already the launcher.
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.exec_cmd("qs -c aphotic ipc call intelligence toggle"), { description = "Toggle Intelligence quick-chat" })

-- Quickshell area picker (drag-select with client snapping + freeze preview) —
-- distinct from the raw grim/slurp/swappy bind on mainMod + S above, which
-- stays as the simple no-frills fallback.
hl.bind(mainMod .. " + SHIFT + S",         hl.dsp.exec_cmd("qs -c aphotic ipc call picker open"), { description = "Screenshot: area picker" })
hl.bind(mainMod .. " + CTRL + S",          hl.dsp.exec_cmd("qs -c aphotic ipc call picker openFreeze"), { description = "Screenshot: area picker (frozen)" })
hl.bind(mainMod .. " + ALT + S",           hl.dsp.exec_cmd("qs -c aphotic ipc call picker openClip"), { description = "Screenshot: area picker to clipboard" })
hl.bind(mainMod .. " + CTRL + ALT + S",    hl.dsp.exec_cmd("qs -c aphotic ipc call picker openFreezeClip"), { description = "Screenshot: area picker (frozen) to clipboard" })

-- Screen capture: eyedropper (click-to-sample a single pixel, copies its
-- hex to the clipboard)
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("qs -c aphotic ipc call colorpicker toggle"), { description = "Pick a color from screen" })

-- Audio output cycling and special-workspace cycling (Quickshell IPC, no
-- other UI path exists for either of these yet)
hl.bind(mainMod .. " + CTRL + O", hl.dsp.exec_cmd("qs -c aphotic ipc call audio cycleOutput"), { description = "Cycle audio output device" })
hl.bind(mainMod .. " + CTRL + Tab",         hl.dsp.exec_cmd("qs -c aphotic ipc call hypr cycleSpecialWorkspace next"), { description = "Next special workspace" })
hl.bind(mainMod .. " + CTRL + SHIFT + Tab", hl.dsp.exec_cmd("qs -c aphotic ipc call hypr cycleSpecialWorkspace prev"), { description = "Previous special workspace" })

-- Window binds
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo(), { description = "Toggle pseudotile" })
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"), { description = "Toggle split direction" })
hl.bind(mainMod .. " + G", hl.dsp.group.toggle(), { description = "Toggle window group" })
hl.bind(mainMod .. " + Q", hl.dsp.window.close(), { description = "Close window" })
hl.bind(mainMod .. " + ALT + Q", hl.dsp.window.kill(), { description = "Force-kill window" })
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen(), { description = "Toggle fullscreen" })
hl.bind(mainMod .. " + CTRL + F", hl.dsp.window.pin(), { description = "Pin window (all workspaces)" })

-- Group navigation
hl.bind(mainMod .. " + CTRL + H", hl.dsp.group.prev(), { description = "Previous window in group" })
hl.bind(mainMod .. " + CTRL + L", hl.dsp.group.next(), { description = "Next window in group" })

-- Alt-tab window switcher
hl.bind("ALT + Tab",         hl.dsp.window.cycle_next(), { description = "Cycle to next window" })
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false }), { description = "Cycle to previous window" })

-- Media keys (mpris — Quickshell's own player service, works with any
-- MPRIS-capable player, not just one hardcoded to a specific app)
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("qs -c aphotic ipc call mpris playPause"), { locked = true, description = "Play/pause media" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("qs -c aphotic ipc call mpris playPause"), { locked = true, description = "Play/pause media" })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("qs -c aphotic ipc call mpris next"),      { locked = true, description = "Next track" })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("qs -c aphotic ipc call mpris previous"),  { locked = true, description = "Previous track" })

-- Laptop binds
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("pamixer -t"),                     { locked = true, description = "Mute/unmute audio" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("pamixer -d 5"),                   { locked = true, repeating = true, description = "Volume down" })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("pamixer -i 5"),                   { locked = true, repeating = true, description = "Volume up" })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("pamixer --default-source -t"),    { locked = true, description = "Mute/unmute microphone" })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl set 10%-"),         { locked = true, repeating = true, description = "Brightness down" })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl set 10%+"),         { locked = true, repeating = true, description = "Brightness up" })

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }), { description = "Focus window left" })
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }), { description = "Focus window right" })
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }), { description = "Focus window up" })
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }), { description = "Focus window down" })

-- Move (swap) the active window with mainMod + SHIFT + arrow keys
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }), { description = "Move window left" })
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }), { description = "Move window right" })
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }), { description = "Move window up" })
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }), { description = "Move window down" })

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }), { description = "Switch to workspace " .. i })
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { description = "Move window to workspace " .. i })
end

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })

-- Jump to the nearest empty workspace
hl.bind(mainMod .. " + CTRL + down", hl.dsp.focus({ workspace = "empty" }), { description = "Jump to empty workspace" })

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Drag window" })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })
