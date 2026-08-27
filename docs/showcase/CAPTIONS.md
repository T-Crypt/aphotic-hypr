# Showcase video — burned-in captions

Silent showcase, no voiceover — these are the lower-third captions
`assemble.sh` burns into `recordings/aphotic-showcase.mp4`. Timestamps
are against the **final assembled video** (offset by the 3s opening
title card ahead of live footage) — see `SHOT_LIST.md` for how each
duration was derived. Scenes 1–11 get a burned-in caption; the open and
close title cards (Scene 12) are static graphics that already carry
their own text, so they don't get a second overlay.

Position: lower-third, left-aligned, clear of the bar (top) and any
centered overlay panel — see `assemble.sh`'s `drawtext` `y` expression.

| # | Start | End | Label (≤8 words) | Description (≤12 words) |
|--:|--:|--:|---|---|
| 1 | 0:03 | 0:07 | Desktop, at rest | HackTheBox theme active, full bar, nothing running |
| 2 | 0:07 | 0:19 | Live theme switching | No rebuild, no relogin — wallpaper and palette update instantly |
| 3 | 0:19 | 0:43 | Bar hover popouts | Hover any status icon for a full detail panel |
| 4 | 0:43 | 1:03 | One launcher, five modes | Apps, clipboard, emoji, windows, wallpapers, projects — one search box |
| 5 | 1:03 | 1:11 | Screenshot picker | Drag-select with live window snapping, plus a freeze-mode variant |
| 6 | 1:11 | 1:21 | Notifications & OSD | Toast popups, on-screen volume and brightness feedback |
| 7 | 1:21 | 1:38 | Command Center | Dashboard, performance, workspaces, wallpapers, and AI chat, one overlay |
| 8 | 1:38 | 2:11 | Settings Control Center | Every category lives in one searchable, full-screen panel |
| 9 | 2:11 | 2:23 | Plugin system | Browse the remote index, install OpenRGB Sync in one click |
| 10 | 2:23 | 2:33 | Lock screen & power menu | Real session-lock protocol, real PAM auth |
| 11 | 2:33 | 2:39 | Terminal games | Snake, hangman, and number-guessing, built into the CLI |
| 12 | 2:39 | 2:42 | *(title card, no overlay)* | Aphotic-Hypr — github.com/T-Crypt/Aphotic-Hypr — GPL-3.0 |

Total runtime: **2:42**.
