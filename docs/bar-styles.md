# Bar styles

The bar used to have one fixed layout with a purely cosmetic skin toggle
(`Settings.barSkin`: `pill`/`square`/`minimal`, just the outer strip's
background treatment). It's now a real swappable bar-**style** system:
four structurally different bar layouts, switchable live from Settings,
a CLI command, or a keybind, without a shell restart.

This is for anyone who wants a different bar shape (a floating dock, a
Windows-style taskbar, an icon-only strip) without hand-editing QML, and
for whoever next touches `Settings.qml`'s bar block and needs to
understand why `barSkin` and `barStyle` are two different properties
that aren't quite redundant.

## The four styles

| Style | What it is | Where it lives | Position support |
|---|---|---|---|
| `full` | The original bar: workspaces, active window, tray, status icons, clock. `pill` (filled, rounded) or `square` (filled, sharp corners) background. | `modules/bar/Bar.qml` (unchanged) | Full left/right/top/bottom + vertical, as before |
| `dock` | Floating macOS-style app dock -- pinned + running apps, icon-proximity magnification, its own auto-hide | `modules/bar/DockWindow.qml` + `DockBar.qml` | Horizontal-first; side placement allowed but flagged (see below) |
| `taskbar` | Windows-style grouped task list with a start button that opens the existing launcher | `modules/bar/TaskbarBar.qml` | Horizontal-first; same flag |
| `minimal` | Thin single-accent-color strip, icon-only except the clock (Omarchy-inspired) | `modules/bar/MinimalBar.qml` | Horizontal-first; same flag |

All four are switchable live -- picking a different one swaps the
running bar's content immediately, no reload.

## Settings schema

Everything lives in `services/Settings.qml`. The full block, in order:

- **`barSkin`** (string, persisted) -- the actual stored value. Historically
  meant only `"pill"`/`"square"`/`"minimal"` as background treatments on
  the one fixed layout. It's now overloaded to also carry `"dock"` and
  `"taskbar"`, and `"minimal"` has been repurposed (see
  [Migration note](#migration-note-the-repurposed-minimal-value) below).
  Kept as the single persisted field instead of adding a parallel
  `barStyle` field to `settings.json`, so there's one value to migrate,
  not two that can drift out of sync.
- **`barStyle`** (readonly, derived) -- `["dock", "taskbar",
  "minimal"].includes(barSkin) ? barSkin : "full"`. This is what
  `BarShell.qml`'s `Loader`, the Settings pane, and every style-scoped
  `visible:` binding actually read. `pill` and `square` both resolve to
  `"full"` here -- they're a sub-choice within the Full style, not a
  fourth and fifth style.
- **`lastFullSkin`** (string, persisted, default `"pill"`) -- remembers
  whichever of `pill`/`square` was last active, so switching *away* from
  Full and back restores your own preference instead of hardcoding
  `pill` every time.
- **`barStyleDefaultsApplied`** (array, persisted) -- style names that
  have already had their first-selection position default applied (see
  `setBarStyle` below). Once a name is in this list, selecting that style
  again never re-applies the default, so a user's own later position
  override sticks.
- **`dockAutoHide`** (bool) -- Dock-only, content-transform auto-hide.
- **`dockPinnedApps`** (array of desktop-entry ids, e.g. `"firefox"`) --
  apps pinned to Dock regardless of whether they're running.
- **`dockMagnification`** (bool, default `true`) -- icon-proximity
  hover-scale on Dock, horizontal placement only.
- **`taskbarGrouping`** (bool, default `true`) -- group Taskbar's task
  list by app instead of one entry per window.
- **`minimalShowDnd`** (bool, default `true`) -- shows the DND toggle
  icon in Minimal's indicator cluster.

### `setBarStyle` / `cycleBarStyle`

```qml
function setBarStyle(name: string): void   // "full" | "dock" | "taskbar" | "minimal"
function cycleBarStyle(): void             // full -> dock -> taskbar -> minimal -> full -> ...
```

`setBarStyle` is the single entry point for changing style -- the
Settings tab, `aphotic bar style <name>`, and the IPC handler all call
through it rather than writing `barSkin` directly, so the
first-selection-position-default and `lastFullSkin` bookkeeping only
exist in one place:

- Selecting `"full"` restores `lastFullSkin` (`pill` or `square`),
  it never resets to a hardcoded default.
- Selecting `dock`, `taskbar`, or `minimal` for the *first time ever*
  (i.e. its name isn't yet in `barStyleDefaultsApplied`) also flips a
  one-time position default: `dock` -> vertical + bottom-anchored,
  `taskbar` -> vertical + bottom-anchored, `minimal` -> vertical + top-
  anchored. Re-selecting the same style later never re-applies this --
  only a name's *first* appearance in `barStyleDefaultsApplied` counts.

An `IpcHandler` with `target: "bar"` at the bottom of `Settings.qml`
exposes `setStyle(name)` and `cycleStyle()` over Quickshell's IPC, which
is what both the CLI and the keybind actually call.

## Dock: a separate floating window, not an edge-docked bar

Unlike the other three styles, Dock isn't rendered inside `BarShell.qml`'s
`Loader` at all -- it's its own `PanelWindow`, `DockWindow.qml`, always
present as a full-screen transparent overlay (`WlrLayershell.exclusionMode:
ExclusionMode.Ignore`) with `visible: Settings.barStyle === "dock"` and a
`Region` mask fitted to the dock pill itself. Same overlay-window pattern
this repo already uses for Notifications/OSD/Dashboard, rather than a
native layer-shell partial-edge-anchor trick -- Dock's floating,
non-edge-spanning geometry doesn't fit a "reserve a strip along one
screen edge" model the way Full/Taskbar/Minimal do.

- **Auto-hide** (`Settings.dockAutoHide`) is content-transform only --
  opacity + a `Translate` that slides the pill off in the direction it's
  anchored, never a re-anchor or re-mask. `shouldShow` is `!dockAutoHide
  || !Hypr.activeToplevel || hovered`: "no window focused" is a rough
  proxy for "nothing to get out of the way of," since a real per-window
  occlusion check isn't cheaply available via Hyprland's IPC.
- **Magnification** (`Settings.dockMagnification`) is `DockBar.qml`'s
  `magnifyFalloff()` -- a quadratic falloff (not linear) from the
  hovered pointer's x position, radius 90px, up to 1.6x scale, so it
  reads as a smooth macOS-style "wave" instead of a hard-edged jump.
  Horizontal placement (`Settings.barVertical`) only -- there's no
  meaningful "distance along the dock" to magnify against in a side
  placement.
- **Pinned apps** (`Settings.dockPinnedApps`) are desktop-entry ids
  merged with live running apps: `DockBar.qml`'s `dockItems` walks
  `dockPinnedApps` first (each resolved via `DesktopEntries`, matched
  against `WindowList.grouped()` to mark it running or not), then
  appends any running app-class group not already covered by a pin, so
  a pinned-but-not-running icon still shows up and a running-but-not-
  pinned app still appears without needing to be pinned first.

## WindowList: shared, event-driven window data

`services/WindowList.qml` is a thin singleton wrapper over Quickshell's
own `Hyprland.toplevels` -- no `hyprctl` polling. It exposes `windows`
(flat, per-toplevel), `grouped()` (by app class, first-seen order
preserved, for Taskbar's task list and Dock's running-state lookup), and
`focus(address)`. Both Dock and Taskbar consume this same service rather
than each maintaining its own toplevel list.

## Taskbar: grouped task list + start button

`modules/bar/TaskbarBar.qml` is a Windows-style horizontal strip: a
start button, then either one entry per running app (`Settings.
taskbarGrouping: true`, the default) or one entry per window
(`false`), then a spacer, then the existing `Tray`/`StatusIcons`/`Clock`.

The start button toggles the *existing* launcher
(`root.screenState.launcher = !root.screenState.launcher`) -- it does
not build a second app menu.

`Tray` and `StatusIcons` have no click handling of their own; Full's
`Bar.qml` normally drives their hover popouts externally via its own
`checkPopout(pos)`. Taskbar had to hand-adapt that same hit-testing
logic into its own `checkPopout`/`nearestAlongChild`/`centerAlong`
(dropping the `barVertical` branching, since Taskbar only ever flows
left-to-right in a single `RowLayout`) -- it's a copy, not a shared
function, so a future change to Full's popout hit-testing needs to be
mirrored here by hand if it should also apply to Taskbar.

## Minimal: thin single-accent strip

`modules/bar/MinimalBar.qml` is a solid-accent-color bar (`Colours.
palette.m3primary` background), icon-only except the clock text.
Left-to-right: workspace dots (`DockWorkspaces.qml`, reused, with its
colours overridden to read against the accent fill), `MinimalIndicators`,
a spacer, `AgentIndicator`, `MinimalTray`, the clock.

`MinimalIndicators.qml` is deliberately scoped to **toggle-type**
indicators only -- things a user flips on/off, currently just DND
(`Settings.minimalShowDnd` gates it, `Settings.dndEnabled` drives it).
Continuous status readouts (wifi signal, battery percentage, etc.) stay
in the full `StatusIcons` cluster and are not duplicated here; a
Minimal-style bar simply doesn't show them. An inactive indicator is
present but invisible (`opacity: 0`, still hoverable to reveal at 0.5),
so more toggle-style indicators (night light, screen-recording, ...) can
be added later without a layout change.

`MinimalBar.qml` also embeds `AgentIndicator` (the multi-provider Claude
Code/Codex/Ollama status glyph) -- it isn't part of the full `StatusIcons`
cluster this bar skips, so Minimal has to place it explicitly or lose it
entirely.

## Settings -> Bar pane

`modules/settings/panes/BarPane.qml` renders four `BarStylePreviewCard`s,
one per style. Each card is a **real, live instance** of that style's
actual top-level component (`Bar`/`DockBar`/`TaskbarBar`/`MinimalBar`),
scaled to ~32%, not a screenshot or a mockup -- against a scratch
`ScreenState` (`modelData: null`) so a preview can't cross-contaminate a
real screen's `settings`/`launcher` flags, and a plain `MouseArea` on top
swallows all interaction (clicking a card calls `Settings.setBarStyle`;
it never drives the miniature bar underneath).

The virtual preview canvas is deliberately sized to `frame width /
scale` and anchored top-left, not given a fixed size and centered. Full,
Taskbar, and Minimal all put their meaningful content at the *edges* of
a full-width bar (start button/tasks on one side, tray/clock on the
other) with an empty `fillWidth` spacer in between. A real bug was found
building this: centering a wide virtual canvas inside a small preview
frame at a fixed scale only ever showed that empty middle slice, never
the actual content. Sizing the canvas to exactly the visible frame's
width (at the preview's own scale) and anchoring top-left instead means
the whole bar, edge to edge, fits the frame at a consistent 0.32 scale
regardless of card size. Dock is the one exception -- it's centered,
since its pill is a compact fixed-size shape, not an edge-to-edge strip.

### The position-mismatch warning

None of Dock/Taskbar/Minimal have a real vertical/side-placement layout
-- all three are horizontal-first designs (see
[Known limitation](#known-limitation-no-real-side-placement) below).
`BarPane.qml` shows a warning banner when
`Settings.barStyle !== "full" && !Settings.barVertical`: a non-Full style
combined with a side placement. This is a deliberate flag, not a block
-- the combination is allowed and won't crash, it's just likely to look
broken, so the pane tells you that instead of either silently allowing
it with no warning or refusing to let you pick it.

## CLI and keybind

`Configs/.local/lib/aphotic/commands/cmd_bar.sh` provides `aphotic bar`,
a thin wrapper around the same `bar` IPC target `Settings.qml` exposes --
it never writes `settings.json` directly:

```bash
aphotic bar style <full|dock|taskbar|minimal>   # qs -c aphotic ipc call bar setStyle <name>
aphotic bar cycle                               # qs -c aphotic ipc call bar cycleStyle
```

`Configs/hypr/keybinds.lua` binds `SUPER+CTRL+SHIFT+B` to `qs -c aphotic
ipc call bar cycleStyle` -- the same cycle order as the Settings pane and
the CLI (`full -> dock -> taskbar -> minimal -> full -> ...`).

## Migration note: the repurposed `"minimal"` value

**If you already have `barSkin: "minimal"` saved in
`~/.local/state/aphotic/settings.json` from before this change, read
this.**

Before this branch, `barSkin: "minimal"` meant "Full-style bar,
transparent fill, border-only outline" -- a purely cosmetic background
treatment on the one fixed layout, with the same workspaces/tray/status-
icons/clock content as `pill`/`square`.

This branch **repurposes the same string value** to mean the new
structural Minimal style instead -- a completely different bar (icon-
only strip, no workspace/status-icon cluster, solid accent background).
This was a deliberate one-time choice, not a bug: anyone with a saved
`"minimal"` value gets the new layout automatically on their next shell
load, with no migration prompt and no fallback to the old outline look.
If you're debugging "my bar changed shape after pulling latest" on an
existing install, this is almost certainly why -- check `barSkin` in
`~/.local/state/aphotic/settings.json`, and switch to `pill` or `square`
from Settings -> Bar (or `aphotic bar style full`, which restores
whichever of the two was last active) if you wanted the old outline
look back. There is no setting that reproduces the old
transparent/outline treatment anymore; it was retired, not renamed.

## Known limitation: no real side placement

Dock, Taskbar, and Minimal are all horizontal-first designs -- none of
them has a real vertical/side-dock layout the way Full does. Settings
still lets you combine any of the three with `Settings.barVertical` /
a side edge; nothing blocks it, and Dock in particular is functional
in a side placement (magnification just disables itself there, per
above). Taskbar and Minimal are more likely to look genuinely broken in
that combination since their layouts assume a full-width horizontal
strip. This is why the Settings pane's warning banner exists (see
above) rather than either hard-blocking a side placement or quietly
shipping it as if it were fully supported -- it's a deliberate, flagged
scope cut for this branch, not an oversight.
