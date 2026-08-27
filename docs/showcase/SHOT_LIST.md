# Showcase video — shot list

Source of truth for `scripts/showcase/run_demo.sh` and
`docs/showcase/CAPTIONS.md`. Every scene below only demos what's actually
shipped on `test` (v1.0 baseline) — nothing from `CLAUDE_ROADMAP.md`,
`ROADMAP_FEATURES.md`, or the README's own Roadmap section. Anything the
README explicitly marks as not wired up (e.g. Settings → Displays' live
resolution/scale editing) is excluded rather than faked.

Each scene lists its **trigger** (the exact command `run_demo.sh` fires,
or `OPERATOR` for a step that needs a real mouse/keyboard interaction the
recorder has to perform by hand — see the note at the bottom), the
**expected result**, and the **duration** `run_demo.sh` sleeps for that
step. Durations sum exactly to the timestamps in `CAPTIONS.md`.

Total live-footage runtime: **156s**. With the open/close title cards
(3s each, produced in `assemble.sh`, no live footage): **162s (2:42)**
final video.

---

## Scene 1 — Cold open (4s)

Desktop at rest: one theme already active (HackTheBox, to match the
README's own Preview), bar visible in its default Full style, nothing
open.

| Trigger | Expected result | Duration |
|---|---|---|
| *(none — just let the recording run)* | Static desktop, wallpaper + bar visible, clock ticking | 4s |

## Scene 2 — Live theme switching (12s)

Same code path `Super+,` / `Super+.` run (`cmd_theme.sh`'s `set`), fired
directly for a deterministic take instead of relying on cycle order.
Wallpaper, accent, and every themed surface (bar, launcher, Settings)
repaint live — no rebuild, no relogin.

| Trigger | Expected result | Duration |
|---|---|---|
| `aphotic theme set hackthebox` | HackTheBox palette + wallpaper apply live | 4s |
| `aphotic theme set nordic` | Nordic palette + wallpaper apply live | 4s |
| `aphotic theme set windows11` | Windows 11 palette + wallpaper apply live | 4s |

## Scene 3 — Bar hover popouts (24s)

`OPERATOR`: hover, in order, the volume/output icon, Wi-Fi, Bluetooth,
battery/power profile, host-info (click to copy the LAN IP), Pomodoro,
and the resource meter — these are all in the grouped status-icon pills
and open on hover. No IPC target opens a specific popout — Bar.qml's
`checkPopout` responds to real pointer position, so this is real mouse
hovering, not scriptable. The Claude Code agent indicator is a separate
element (not part of the status-icon pills) and opens on **click**, not
hover — see `AgentIndicator.qml`'s `onClicked`; include it as a
left-click in this scene, not another hover.

| Trigger | Expected result | Duration |
|---|---|---|
| `OPERATOR` — hover each status icon in sequence | Each hover opens that icon's real detail popout (`popouts/*.qml`) | 20s |
| `OPERATOR` — left-click the Claude Code agent indicator, then click again to close | Agent panel opens/closes (toggle, not hover) | 4s |

## Scene 4 — Launcher modes (20s)

`Super+A` opens app search; typing a prefix character switches mode
inside the same box. `run_demo.sh` types the prefix with `wtype` if it's
installed, otherwise prints the character to type manually — see the
dependency note below.

| Trigger | Expected result | Duration |
|---|---|---|
| `qs -c aphotic ipc call launcher toggle` | Launcher opens in app-search mode | 3s |
| type `>` | Clipboard history (`cliphist`), pin icon visible | 3s |
| type `:` | Emoji picker | 3s |
| type `/` | Open-window switch list | 3s |
| type `~` | Wallpaper picker | 3s |
| type `@` | Project jump (terminal + `claude` + editor) | 3s |
| `qs -c aphotic ipc call launcher toggle` | Launcher closes | 2s |

## Scene 5 — Screenshot picker (8s)

Real Quickshell picker, not the plain `grim`/`slurp`/`swappy` combo on
`Super+S`. `OPERATOR`: the actual drag-select is a mouse gesture.

| Trigger | Expected result | Duration |
|---|---|---|
| `qs -c aphotic ipc call picker open` + `OPERATOR` drag-select | Region select with live client-window snapping | 4s |
| `qs -c aphotic ipc call picker openFreeze` + `OPERATOR` drag-select | Screen freezes first, then drag-select on the frozen frame | 4s |

## Scene 6 — Notifications + OSD (10s)

| Trigger | Expected result | Duration |
|---|---|---|
| `notify-send "Aphotic" "Showcase notification" -a Aphotic` | Toast popup, top-right | 3s |
| `pamixer -i 5` (same command `XF86AudioRaiseVolume` runs) | Volume OSD popup | 3s |
| `qs -c aphotic ipc call brightness set 40%` | Brightness OSD popup, dims | 2s |
| `qs -c aphotic ipc call brightness set 90%` | Brightness OSD popup, brightens | 2s |

> On the recording machine this must be quickshell's own active
> notification daemon (`org.freedesktop.Notifications`) for the toast to
> land — if another daemon (mako, dunst, …) already owns that DBus name,
> `notify-send` will render through that instead and the scene won't
> match. `qs -c aphotic` logs `Could not register notification server at
> org.freedesktop.Notifications, presumably because one is already
> registered` on startup when this is the case — check for that line, or
> stop the competing daemon, before recording this scene. `aphotic
> doctor` doesn't check for this itself.

## Scene 7 — Command Center (17s)

`Super+D`. Only `dashboard.toggle` is exposed over IPC — switching tabs
inside it is `OPERATOR`.

| Trigger | Expected result | Duration |
|---|---|---|
| `qs -c aphotic ipc call dashboard toggle` | Opens on the Dashboard tab (clock/calendar/media, weather, Pomodoro, quick toggles) | 3s |
| `OPERATOR` click Performance tab | Live CPU/GPU/memory/storage/network cards | 3s |
| `OPERATOR` click Workspaces tab | Numbered grid, click-to-jump | 3s |
| `OPERATOR` click Wallpapers tab | Cycle/pick within the active theme, live | 3s |
| `OPERATOR` click AI Chat tab | Provider pills (Claude/Ollama/Gemini/ChatGPT[/Assistant]) | 3s |
| `qs -c aphotic ipc call dashboard toggle` | Closes | 2s |

## Scene 8 — Settings Control Center (33s)

`Super+I`. Only `settings.toggle` is exposed over IPC — the category
rail itself is `OPERATOR`.

| Trigger | Expected result | Duration |
|---|---|---|
| `qs -c aphotic ipc call settings toggle` | Opens on Appearance: theme grid | 3s |
| `OPERATOR` click **Browse all wallpapers** | Grid spanning every theme | 3s |
| `OPERATOR` click **Theme Creator** | Build a palette live (background/foreground/cursor + 16 ANSI, HSV wheel) | 4s |
| `OPERATOR` click **Personalization** | Accent override + per-icon color overrides | 3s |
| `OPERATOR` click **Bar** | Style previews (Full/Dock/Taskbar/Minimal), orientation toggle | 3s |
| `OPERATOR` click **AI** | Provider config + Ollama model manager | 3s |
| `OPERATOR` click **Power & Security** | Power profile switcher, idle timeouts | 3s |
| `OPERATOR` click **Workspace Profiles** | Named launch-group list | 3s |
| `OPERATOR` click **Plugins** | Installed list + Browse available (see Scene 9) | 3s |
| `OPERATOR` click **System** | Live `aphotic doctor` output | 3s |
| `qs -c aphotic ipc call settings toggle` | Closes | 2s |

> Settings → **Displays** is deliberately excluded: the README documents
> it as read-only info (name/resolution/refresh/scale/primary badge) —
> live resolution/scale editing isn't wired up yet.

## Scene 9 — Plugin system (12s)

| Trigger | Expected result | Duration |
|---|---|---|
| `aphotic plugin list --remote` (in a terminal) | Prints the remote index: `openrgb`, `direnv`, `workspace-session-log` | 4s |
| `qs -c aphotic ipc call settings toggle` + `OPERATOR` navigate to Plugins, click **Install** on OpenRGB Sync | Clones the plugin, moves it into the Installed list | 6s |
| `qs -c aphotic ipc call settings toggle` | Closes | 2s |

## Scene 10 — Lock screen + session menu (10s)

`lock.unlock` is used instead of typing a real password on camera — same
PAM-backed lock either way, just skipping the typed-credential beat.

| Trigger | Expected result | Duration |
|---|---|---|
| `qs -c aphotic ipc call lock engage` | Real `ext-session-lock-v1` lock screen | 3s |
| `qs -c aphotic ipc call lock unlock` | Unlocks | 2s |
| `qs -c aphotic ipc call session toggle` | Session/power menu: lock, suspend, log out, hibernate, reboot, shut down | 3s |
| `qs -c aphotic ipc call session toggle` | Closes | 2s |

## Scene 11 — Terminal games (6s)

Games are interactive (need real keypresses to play) — the beat is the
attract screen, not a full playthrough.

| Trigger | Expected result | Duration |
|---|---|---|
| `kitty -e aphotic play snake` | Snake's terminal UI opens | 4s |
| `OPERATOR` close the game terminal | — | 2s |

## Scene 12 — Close (3s, title card only)

Not live footage — a generated still (wordmark, GitHub URL, GPL-3.0),
produced by `assemble.sh` (see Step 5). See `CAPTIONS.md` for the exact
text.

---

## Dependency notes

- **`wtype`** (optional) — used in Scene 4 to type launcher prefix
  characters. If it isn't installed, `run_demo.sh` prints the character
  to type by hand and keeps going; install it (`pacman -S wtype`) for a
  fully hands-off Scene 4.
- **`wf-recorder`** (required to actually record) — see
  `scripts/showcase/record.sh`.
- Every `OPERATOR` step still gets its full sleep window and a labeled
  cue on stderr — see `run_demo.sh`'s `operator()` helper. These are the
  interactions this shell has no IPC/CLI surface for (hover, tab clicks,
  drag-select); nothing was invented to avoid them.
