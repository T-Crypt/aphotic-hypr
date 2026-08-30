> **Archived 2026-08-30.** Already superseded by `docs/LEDGER.md` per `BACKLOG.md`'s own document map; now also folded into [`docs/APHOTIC_UNIFIED_VISION.md`](../APHOTIC_UNIFIED_VISION.md)'s Historical/Superseded section. Kept for history only.

# In Flight

**See `docs/LEDGER.md` first.** As of 2026-08-28 that's the unified
tracking log — active bugs, half-implemented/undocumented/unkeybound
items, and the queued-next list all live there now, consolidated out of
this file's old "Corrections"/"Dead code and stubs found in passing"
sections (removed below, superseded by the Ledger) and the review that
found the GPU/temp/launcher-pane issues.

This file stays as the detailed session-log history — what was worked
on, why it was done a particular way, blow-by-blow — for the entries
already below. New entries of that shape can still go here; anything
that's just a tracked open item (bug, gap, TODO) belongs in the Ledger
instead so it isn't duplicated in two places.

`docs/ROADMAP.md` is the long-lived feature backlog. Anything that lands
and stops moving gets folded into `ROADMAP.md`'s Shipped section and
deleted from here.

---

## Done — Bar sizing budget (2026-08-28)

**The bug.** Bar entries were pushed outside the bar's own margins and off
the screen. Reproduced live: five windows open on the active workspace on a
1080px-tall vertical bar put the power button entirely off the bottom edge.

**Root cause.** Sizing had a feedback edge in it. `Bar.qml` derived its own
`implicitWidth`/`implicitHeight` from `activeLayout`'s content size while
the Loaders below were simultaneously sizing that layout *from* `Bar`, and
`width: implicitWidth` / `height: implicitHeight` then discarded the
screen-sized box `BarShell.qml`'s `Loader { anchors.fill: parent }` had
handed it. Three consequences at once:

1. the bar lost its only tie to a real screen dimension;
2. `vColumn.height` collapsed to `vColumn.implicitHeight`, so the two
   `Layout.fillHeight` spacers had zero surplus to absorb and contributed
   nothing — the column had no compression mechanism at all;
3. the workspace row's growth (roughly 220px → 700px purely on which apps
   are open, with the defaults of 5 shown × 5 window icons) added straight
   to the total and shoved everything after it past the strip.

`ActiveWindow.qml` made it worse: its `maxExtent` summed its *siblings'
rendered* `width`/`height`, which are outputs of the very layout pass that
value feeds.

**The fix — a sizing budget with a one-way flow.**

    screen -> contentExtent -> per-entry grant -> the entry's real size

Nothing to the right of an arrow may feed back into anything to its left.
Concretely:

- `Bar.qml` derives `alongExtent` from `screen`, never from content, and
  `contentExtent` from that minus `vPadding` and inter-entry spacing.
- Every entry declares three numbers instead of one implicit size:
  `minAlong` (hard floor), `baseAlong` (full structure, no optional
  detail), `desiredAlong` (everything). Inelastic entries leave all three
  at their implicit size and are never asked to shrink.
- Room is handed out as a priority ladder, so the bar sheds *detail*
  before it sheds *structure*: (1) everyone gets `minAlong`; (2) leftover
  goes toward the structural gap `base - min`, shared in proportion to each
  entry's own gap; (3) only once every base is covered does anything go
  toward `desired - base`. Proportional sharing means two elastic entries
  degrade together rather than the first-listed one starving the rest.
- `EntryWrapper` allocates the grant via `Layout.preferredWidth/Height`,
  caps every entry at `contentExtent`, sets an explicit `0` minimum along
  the bar's length (QtQuick.Layouts overflows rather than shrinking below a
  child's minimum hint), and binds the child item to the size it was
  actually granted as a last-resort guarantee.
- The two elastic entries reduce their own detail rather than being clipped:
  - `ActiveWindow.qml` takes `maxExtent` top-down and elides its title
    against it. Its `baseExtent` is the app icon plus padding — the icon
    always survives.
  - `Workspaces.qml` treats window icons as optional detail with a real
    budget, sharing them out round-robin (every occupied workspace gets its
    1st icon before any gets its 2nd), and paginates to fewer cells
    (`effectiveShown`) when the bar is too short to hold all of them.

**Two binding loops were found and fixed while building this.** Both
produced the same symptom — Qt breaks a loop by freezing the property one
evaluation short, so a stale value silently persists:

- `ActiveWindow.qml`: `desiredExtent` read `metrics.advanceWidth` while
  `metrics.elideWidth` was computed from `desiredExtent`. QQuickTextMetrics
  notifies its outputs together, so reading *any* of them registers on a
  signal that `elideWidth` also fires. Fixed with a second, elide-free
  `TextMetrics` (`naturalMetrics`) used only for measurement.
- `Workspaces.qml`: `effectiveShown` from the full grant, while the icon
  demand the grant is computed from is measured per visible cell. Fixed by
  splitting the grant into two channels — `structuralAlong` (rungs 1+2,
  free of any `desiredAlong` dependency) decides `effectiveShown`;
  `grantedAlong` (rung 3) decides the icon budget.

**Also fixed in the same subsystem:**

- `Bar.qml` `EntryWrapper` dereferenced `root.activeRepeater.count` without
  `?.`, which throws inside a margin binding during an orientation swap.
  Now reads `root.entryCount`.
- `Workspace.qml`'s window-icon `Grid` sized `rows`/`columns` off
  `children.length`, which counts the `Repeater` itself — one over. Now
  counts the Repeater's own `count`.
- `ActiveIndicator.qml` / `OccupiedBg.qml` wrapped their workspace indices
  on `Config.bar.workspaces.shown`; with pagination that can point at a
  cell that isn't rendered. Both now wrap on `workspaces.count`.
- `SpecialWorkspaces.qml`: removed a self-referential
  `Layout.preferredHeight: implicitHeight` on a `Layout.fillHeight` Loader.
- `BarWrapper.qml`: removed `clampedWidth`, declared and never read.
- `ActiveWindow.qml`: removed its `Behavior on implicitWidth/implicitHeight`
  — `EntryWrapper` animates the allocation now, and two animations
  describing the same resize fight each other.

**Verified live** (single 1920×1080 output, `barStyle: "full"`) in both
orientations: baseline; five and six windows on the active workspace;
`Config.bar.workspaces.shown` temporarily raised to 15; a
70-character window title; workspace switching; and hover popouts. No
binding loops and no QML errors in `qs -c aphotic log` after a clean
`aphotic reload`.

### Known gaps left in the bar

- **Multi-monitor was not exercised** — only one output was available on
  the test machine. The budget reads `bar.screen.width`/`.height` per
  `BarWindow` instance, which is per-monitor by construction (`Variants`
  over `Quickshell.screens`), so it should hold, but it has not been seen
  running on two outputs of different sizes. Worth a look on real hardware.
- **`Tray.qml` cross-axis soft cycle** — `nonAnimHeight` reads `root.width`
  and `nonAnimWidth` reads `root.height` (`Tray.qml:22-47`). It terminates
  today only because whichever of those is the cross axis resolves to the
  constant `Settings.barInnerWidth`. Only reachable with
  `Config.bar.tray.compact` *and* `background` on (both default off). Not
  touched here; worth rewriting to read the constant directly.
- **`StatusIcons` is inelastic and large** — ~13 enabled icons across three
  pills. On a genuinely short screen it is the entry that will consume the
  budget. If that ever bites, the natural fix is to make its trailing group
  elastic (a "+N" overflow pill) using the same three-number contract every
  other entry now speaks.
- **Only `Bar.qml` (the "full" style) runs a budget.** `TaskbarBar.qml`,
  `MinimalBar.qml` and `DockBar.qml` still size purely from content. They
  are horizontal-only and carry far fewer entries, so they have much more
  headroom, but they have the same structural weakness. Both elastic
  components default their budget properties to `-1` (= unconstrained), so
  they work unchanged in those hosts today.

---

## Done — Shared hover affordance across every bar style (2026-08-28)

**What was asked for.** The gliding hover highlight that the Full/Taskbar
status-icon pills had should feel identical in all four dock orientations
and in every bar style — Full, Taskbar, Dock, Minimal — and the workspace
strip should highlight whichever workspace you would switch to, empty ones
included.

**The bug underneath it.** `StatusIcons.qml`'s indicator computed its
diameter from `pillContainer.height` in both orientations. That is the
cross axis only when the bar is vertical; on a horizontal bar the same
expression returns a single icon row's height, so the highlight shrank to
*smaller than the icon it was meant to sit behind*. It now reads the host
pill's real cross-axis thickness.

**Two new shared components**, both in `modules/bar/components/` and
registered in that directory's `qmldir`:

- **`HoverPill.qml`** — the gliding circle itself. Contract: it is a
  *sibling* of the row/column holding the icons (it positions itself in
  their shared parent's coordinate space via `container.x`/`container.y`),
  and takes `container`, `hoveredEntry`, and `thickness` (the cross-axis
  room available). It animates `centerAlong` rather than x/y directly,
  which is what makes it glide between neighbours instead of reappearing
  at the new one, and it holds the last centre while fading out so the
  exit doesn't drag the pill back to the start of the row.
- **`BarHit.qml`** (singleton) — `nearestAlong(container, pos)` /
  `nearestAt(container, x, y)`. Nearest-centre rather than a rect test, so
  the cursor never falls into a dead zone in the gap between two icons.
  `Bar.qml`, `TaskbarBar.qml` and `StatusIcons.qml` each carried their own
  copy of this logic; the switch-over point between two adjacent icons is
  half of what "the same feel" means, so it now can't drift between styles.

**Wired into:**

| Style | Surface |
| --- | --- |
| Full | `StatusIcons.qml` pills, `workspaces/Workspaces.qml` |
| Taskbar | `StatusIcons.qml` pills (shared component) |
| Dock | `DockBar.qml` app-icon row, `DockWorkspaces.qml` |
| Minimal | `MinimalIndicators.qml`, `MinimalTray.qml`, `DockWorkspaces.qml` |

**Workspace highlight.** `Workspaces.qml` (Full) and `DockWorkspaces.qml`
(Dock/Minimal/Taskbar) now highlight the cell under the pointer whether or
not it is occupied — an empty workspace is still somewhere you can switch
to. The click hit-test was switched to the same `BarHit` call as the
highlight, so a click landing where the highlight clearly showed a target
no longer does nothing: `childAt()` previously returned null in the gap
between two cells.

**Dock magnification interaction.** The Dock already magnifies icons under
the pointer. A gliding pill *plus* magnification read as two competing
affordances, so the dock shows one or the other: the pill is active only
when `Settings.dockMagnification` is off, and `DockAppIcon`'s own
`StateLayer` hover tint is suppressed while the pill is on (same circle,
same 0.08 opacity — leaving both would double the tint and hide the glide).

### Not verified live
Hover cannot be scripted in this environment — warping the cursor with
`hl.dsp.cursor.move` does not deliver pointer-enter events to a
layer-shell surface, so neither the highlight nor the hover popouts fire.
Full and Dock/Minimal reload with no QML errors and no binding loops, and
the Full workspace highlight was confirmed by hand. **Still needs a manual
pass:** Taskbar and Minimal styles, and the horizontal orientation of each.

### Surfaced while doing this — pre-existing, not fixed
- **Minimal is broken in side placement.** `MinimalBar.qml` lays out as a
  `RowLayout` unconditionally, even when `Settings.barHorizontal` is false,
  and its own `implicitWidth`/`implicitHeight` ternaries look inverted —
  so `BarWrapper` hands it a thin *tall* strip and the whole style
  overflows. Independent of the hover work; the shared components branch on
  `Settings.barHorizontal` internally and will be correct for free once the
  style is made to reorient.
- **`DockWorkspaces.qml` was horizontal-only too** and has been made
  orientation-aware as part of this (a `GridLayout` with a `flow`, swapped
  dot extents). Horizontal output is unchanged; vertical now stacks instead
  of overflowing the 48px dock pill.
- **`StateLayer` has a dead `showHoverBackground` property** that looks
  intended for exactly the "suppress my own hover tint" job `DockAppIcon`
  now does with a new `showHover` flag, but it is not wired to
  `stateOpacity`. Worth reconciling.

### Tooling note for whoever picks this up
`qmllint` on `$PATH` is **Qt 5**'s and exits 255 with no output on every
file in this repo, including untouched ones — it validates nothing. The
real binary is `/usr/lib/qt6/bin/qmllint`, and it needs an import root
containing a `qs` symlink to `Configs/quickshell/aphotic` to resolve
`qs.*`. Even then the useful signal is thin: the nested-`QtObject`
singleton pattern (`Tokens`, `Colours`, `Config`) produces constant
`Member "..." not found on type "QObject"` noise. **The reliable check is
`qs -c aphotic log` after a reload** — it reports real type errors,
non-existent property assignments and binding loops.

---

## Done — Toaster, grid keyboard nav, static Colours.qml, uniform IPC toggle, launcher Settings search (2026-08-28)

All five items from the previous "Next up" batch below, in order.
**Uncommitted** — sitting as local working-tree changes only, not
committed or pushed. Whoever picks this up next should `git diff`/`git
status` first rather than trusting this doc alone for exact state.

1. **`Toaster.toast()`** now shells out via `notify-send` (`-a aphotic`,
   `-i <icon>` when non-empty), matching the six other call sites already
   doing this. Also found and fixed a second bug blocking 3 of its 5
   callers: `Audio.qml`/`Players.qml` gated their calls on
   `GlobalConfig.utilities.toasts.*`, a config path that was referenced
   but never declared anywhere — reading it threw and aborted before
   `toast()` was ever reached. Added the missing `GlobalConfig.utilities`
   schema (three bools, default `true`).
2. **Grid launcher keyboard nav** — `Keys.onDown/UpPressed`/`onReturnPressed`
   now branch on `root.useGrid`, driving `grid.moveCurrentIndexUp/Down()`
   (real 2D row-wrap, not `list`'s 1D increment) and reading
   `grid.currentItem` when grid style is active. Added a real `execute()`
   to `AppGridItem.qml`. Verified live with real `wtype` keypresses —
   highlight moves correctly, confirmed via screenshots.
3. **`Colours.qml`** is a static file now — no longer wallust-templated.
   It reads the resolved palette from `~/.local/state/aphotic/palette.json`
   at runtime via a `FileView` (same file the plugin system already
   reads), extended with two new derived fields (`surfaceContainer`/
   `surfaceContainerHigh`, computed wallust-side via `darken`/`lighten` so
   there's one color-math implementation, not two). `wallust.toml`'s
   `quickshell` template entry and `colors-quickshell-colours.qml` are
   gone. `tests/test_repo_layout.sh` gained a regression guard (fails if
   `{{` Jinja syntax ever reappears in the tracked file). Verified via
   real theme switches that the tracked file now stays byte-identical.
   Root type had to change `QtObject` → `Singleton` (`FileView` needs a
   default-property host `QtObject` doesn't provide) — caught this live,
   not by inspection.
4. **Uniform `toggle(<name>)` IPC dispatcher** — `shell.qml` now has one
   `IpcHandler { target: "aphotic"; function toggle(name) }` backed by a
   `_toggleTargets` name→function map; the original 9 shell.qml targets
   plus `colorpicker` are kept as thin aliases calling into the same map
   (verified back-compat live: old `qs ipc call launcher toggle` still
   works). Unknown names warn via `console.warn`, don't throw. Existing
   `Configs/hypr/keybinds.lua`/`cmd_bar.sh` call sites were **not**
   rewritten — back-compat means there's no functional need to, and
   touching 25 already-working keybind lines for zero behavior change
   wasn't worth the risk.
5. **In-launcher Settings search** — `?` prefix (every other punctuation
   sigil was already taken). Categories hoisted from `SettingsPanel.qml`
   into `config/SettingsCategories.qml` (singleton) so the launcher and
   the Settings panel's own category rail share one list instead of two
   that can drift. New `ScreenState.settingsCategory` (one-shot handoff,
   same shape as the existing `launcherPrefill`), new
   `modules/launcher/SettingsItem.qml` delegate, `SettingsWindow.qml`
   consumes the handoff on `visible` becoming true. Verified live:
   `?bar` → filtered result → Enter opens Settings directly on the Bar
   pane; keyboard nav to a non-first result (Personalization) opens the
   right pane too, not just index 0.

### Known follow-up, not done
`docs/cli.md`'s IPC section and `scripts/showcase/run_demo.sh` (the
latter no longer exists — the whole `scripts/showcase/` tree was removed
in an earlier, unrelated cleanup pass) were listed as call sites to touch
for item 4; skipped since back-compat aliases make it optional, not because
it was overlooked.

---

## Done — Keybinds cheatsheet, notification DND row, desktop right-click menu, calculator (2026-08-28)

Picked from `docs/IDEAS.md`'s near-term backlog after a verification pass
found 6 of the original 12 items already shipped (see that doc's
corrections). **Uncommitted** — local working-tree changes only.

1. **Keybinds cheatsheet** (`!` launcher prefix) — built on `hyprctl
   binds -j`, not by parsing `keybinds.lua`, per the correction already
   on record below. That only works because `hl.bind()` turns out to
   accept a `description` option that `hyprctl binds -j` faithfully
   echoes back (`has_description`/`description` fields existed in the
   schema but were unused) — confirmed live before committing to the
   approach, not assumed from the correction note alone. Added a
   description to all 86 binds in `keybinds.lua`. New
   `services/HyprKeybinds.qml` singleton parses the live bind table
   (modmask → "SUPER+SHIFT" style labels, XF86 key prettification),
   filtered to described binds only. New `modules/launcher/KeybindItem.qml`
   delegate — Enter copies the combo to clipboard via `wl-copy` +
   `Toaster.toast()` confirmation (a keybind isn't "launchable" the way
   an app is; copying the combo for pasting elsewhere is the useful
   action). Verified live: `!lock` → single filtered result → Enter →
   clipboard confirmed holding `SUPER+L`; browsing with no query lists
   all 86 alphabetically; keyboard nav confirmed via screenshot.
2. **Notification quick-toggles row** — DND toggle icon added to
   `NotificationCenterContent.qml`'s header (between "Mark all read" and
   close), reusing `DoNotDisturb.enabled`/`.toggle()` directly, styled to
   match the existing close-button pattern in the same file. The
   optional "clear all" button from the original idea was dropped —
   `NotificationHistory.qml` (what this panel displays) only has
   `deleteEntry(id)`, no bulk-clear; `Notifs.qml`'s `clear()` IPC handler
   clears a different list (live popups) and would have been wired to
   the wrong data. Verified live: icon renders unfilled/muted when DND
   is off, filled/primary-color when on, toggling via the real IPC path
   flips `settings.json`'s `dndEnabled` correctly both directions.
3. **Desktop right-click context menu** — flat 2-item menu (no nested
   submenus): "Wallpapers & Themes" reuses the exact same
   `launcherPrefill = "~"` path `SUPER+CTRL+W` already triggers;
   "Settings" reuses the `_toggleTargets.settings` path from item 4's
   dispatcher. New `modules/background/DesktopContextMenu.qml`, wired
   into `BackgroundWindow.qml` via a `TapHandler(RightButton)` (observes
   without grabbing, so normal left-click-through stays untouched) plus
   a `z:100` `Loader` (background-layer siblings stack by declaration
   order otherwise, which would have buried the menu under the
   wallpaper). **Not independently verified**: no pointer-simulation
   tool exists in this environment (`ydotool`/`wlrctl`/`dotool` all
   confirmed absent; `wtype` is keyboard-only) — the right-click
   *trigger* itself was verified by code review only (correct
   `TapHandler` button filter, nothing else grabbing input first), not
   by an actual simulated click. The menu's *rendering* was verified live
   by temporarily forcing it open. **Worth a real right-click test.**
4. **Calculator applet** (`=` launcher prefix) — reconciles the
   README.md:150 non-goal ("things needing a native C++ plugin... were
   left out," calculator listed as an example): a basic calculator
   doesn't actually need native code, just an expression parser, so the
   non-goal's reasoning doesn't apply here once separated from the other
   two examples in that list (fingerprint auth, matugen) that plausibly
   still do. Real recursive-descent parser/evaluator inline in
   `Launcher.qml` (`_evalMath`) — deliberately never `eval()`/`Function()`
   on live untrusted input. Supports `+ - * / % ^ ()` and unary +/-.
   Invalid expressions return `null` → empty result list, not a
   NaN/broken row. New `modules/launcher/CalculatorItem.qml` — Enter
   copies the formatted result to clipboard (same `wl-copy`+`Toaster`
   pattern as item 1). Verified live: `=(12+8)/4*3-1` → `14` (checked
   against manual arithmetic); Enter → clipboard confirmed holding `14`
   → then `=7*6` → Enter → clipboard confirmed holding `42`;
   `=2+*3` (malformed) → empty result list, no crash, `qs log` clean.

### Explicitly declined this batch
Wallpaper auto-cycle — the other genuinely-open near-term item — was
offered but not selected for this batch; still open, see `docs/IDEAS.md`.

### Caught during wrap-up, not this batch's fault
`Settings.barSkin` had drifted from `"dock"` to `"pill"` by the time this
batch finished — almost certainly a forked agent's own live-testing
leaving state unrestored despite being told to restore it. Caught by a
final settings.json check and fixed before wrap-up. Worth remembering:
when running multiple agents with overlapping live-desktop testing in
the same session, a final cross-check of shared mutable state (bar
style, launcher style, open panels) after everything reports done is
not optional, even when each agent individually claims it restored its
own state.

---

## In progress — Wallpaper Picker (scaffold) (2026-08-28)

**Branch:** `feature/wallpaper-picker`. Not merged to `test`/`main`.

**What.** A new `modules/wallpaperpicker/` — a fast, large-preview,
horizontal-filmstrip wallpaper switcher taking over `SUPER+W` (currently
a random-pick keybind). Omarchy-style filmstrip, caelestia-style live
feel.

**Why.** Wallpaper browsing today lives in three places, none of them a
fast dedicated "glide through and pick" surface: Settings → Appearance's
`WallpaperPicker.qml`/`WallpaperTile.qml` grid (cross-theme), the
launcher's `~` prefix mode (also cross-theme), and the Command Center
Dashboard's Wallpapers tab (`DashWallpapersTab.qml` — in-theme prev/next,
but **text-only, no image preview at all**). This closes that gap
specifically for "I'm in a theme, I want to see and pick a wallpaper
fast" — deliberately narrower than the existing cross-theme surfaces, not
a replacement for them.

**Scope boundary, explicit:** this REPLACES `SUPER+W`'s random-pick
behavior with opening the picker. It does NOT remove or consolidate the
Settings grid or the Dashboard tab — those stay exactly as-is. See the
"Flagged for later" note below for why that boundary is already looking
questionable.

### Naming collision caught before writing any code
The obvious name — `WallpaperPicker.qml` — is **already taken** by the
Settings → Appearance grid component (`modules/settings/panes/
WallpaperPicker.qml`). Different QML namespace (`qs.modules.settings.panes`
vs. the new `qs.modules.wallpaperpicker`) so it would technically compile,
but two same-named components is a real footgun for anyone grepping this
tree later. Using `WallpaperPickerWindow.qml` for the root instead —
matches the existing `LauncherWindow.qml`/`DashboardWindow.qml` naming
convention (thin `PanelWindow` host, separate from the actual content
component) anyway, so this isn't a compromise, it's the naming this repo
already uses for exactly this shape.

### Structural precedent: launcher, not areapicker
Corrected mid-research: `areapicker/AreaPicker.qml` is a full-screen
crosshair drag-select tool, not a centered dialog — wrong precedent for
"large centered surface with room around it." `LauncherWindow.qml` /
`DashboardWindow.qml` are the real match: full-screen transparent
`PanelWindow` (`WlrLayer.Overlay`, `color: "transparent"`, all 4 anchors
true) hosting a `MouseArea` click-outside-dismiss + `Keys.onEscapePressed`,
with the actual content `anchors.centerIn: parent`. Copying that shape
for `WallpaperPickerWindow.qml` + `WallpaperFilmstrip.qml`.

**No backdrop blur/dim exists anywhere in this repo's overlays** — checked
launcher, Dashboard, every full-screen host. "Desktop visible behind the
picker" is just this same transparent-host-plus-opaque-floating-panel
shape everything else already uses, not a new blur layer. Real backdrop
blur would be new, unproven-in-this-codebase work — not doing that in a
scaffold pass.

### Backend decision — resolved, not left open
The task brief flagged live-preview-per-scroll vs. thumbnail-until-commit
as a decision to make during implementation because live-applying looked
like it might mean a subprocess call per scroll notch. It doesn't:
`Themes.qml`'s `setWallpaperInActiveTheme(file)` already updates
`activeWallpaper` synchronously (whatever's bound to it, including a
filmstrip highlight, updates instantly) and applies the real wallpaper
in-process through an existing 200ms debounce `Timer` — rapid repeated
calls already collapse into one real apply for whatever the caller last
settled on. This is the exact mechanism Settings/Dashboard already rely
on. So: **true live-preview on every scroll step**, calling
`Themes.setWallpaperInActiveTheme(file)` directly — no subprocess, no
`wallswitcher.py` involvement in the interactive path at all.
`wallswitcher.py` stays relevant only as the CLI/legacy random-pick path.

**Consequence this decision creates, handled in the scaffold:** since
scrolling now live-applies for real, "Escape closes without changing
anything" requires snapshotting `Themes.activeWallpaper` on open and
calling `setWallpaperInActiveTheme` back to it on Escape — otherwise
Escape wouldn't actually revert anything, since the desktop already
changed live while gliding past it.

### Filmstrip orientation — horizontal always, my call
The brief asked whether this should adapt to bar orientation. Decision:
stays horizontal regardless of `Settings.barHorizontal` — this is a
deliberate takeover surface like the launcher, not something docked
relative to the bar, and the launcher itself doesn't reorient with the
bar either. Flagging this as my call per the brief's instruction to make
one and note it, not asking for it back.

### Thumbnails — no cache exists, none built
`WallpaperItem.qml` (launcher) and `WallpaperTile.qml` (Settings grid)
both just point `Image.source` at the real file directly
(`asynchronous: true`, `cache: true` for Qt's in-memory pixmap cache,
`sourceSize` bounded to cap decode cost) — no disk thumbnail pipeline
exists anywhere in this repo to reuse or extend. Filmstrip does the same:
real files, bounded `sourceSize`, Qt's own downscaling. A real thumbnail
cache is future work if wallpaper counts/resolutions ever make this feel
slow, not part of this scaffold.

### IPC
`target: "wallpaperpicker"`, added to `shell.qml`'s existing
`_toggleTargets` map (`wallpaperpicker: () => {...}`) plus a thin
`IpcHandler` alias — same shape as every other surface added this
session (settings, colorpicker, etc.).

### Keybind change
`SUPER+W`: `wallswitcher.py` (random pick) → `qs -c aphotic ipc call
wallpaperpicker toggle`. `SUPER+CTRL+W` (`launcher openWallpapers`,
cross-theme browse) is **left as-is** — it opens a genuinely different,
already-existing surface, not superseded by this one.

Random-pick is not lost: `aphotic wallpaper --random` (CLI, already
exists) still reaches the same `wallswitcher.py` logic. It just no longer
has a dedicated keybind. **Flagging, not deciding:** losing one-key
access to "surprise me" might be worth a replacement bind — not picking
one unilaterally since that's a real keybind-real-estate decision.

### Flagged for later, not this pass
Raised independently by Trevin mid-task, matching the scope-boundary
flag the brief itself asked for: once this ships, wallpaper browsing has
**four** entry points (Settings grid, Dashboard tab, launcher `~` mode,
this picker). The Dashboard Wallpapers tab is the weakest of the four —
no visual preview at all, and this new picker covers the exact same
in-theme prev/next scope it does, just with an actual image. Worth a real
consolidation discussion — likely removing/repurposing
`DashWallpapersTab.qml` in favor of this picker plus the Settings grid —
but **explicitly not happening in this pass**. Revisit once the picker
has shipped and had some real use.

**Status:** scaffold phase — filmstrip, scroll/keyboard interaction, live
apply, and open/close working end-to-end for one theme's wallpaper set.
Not polished across every theme's wallpaper count/aspect ratio.

## Polish pass — Wallpaper Picker motion/visual refinement (2026-08-28)

**What changed** (`WallpaperFilmstrip.qml` only, no scope change to
`WallpaperPickerWindow.qml`/IPC/keybinds): replaced the scaffold's
discrete arrow-key/wheel-notch stepping with continuous, momentum-based
motion built on `Flickable`'s native physics rather than a hand-rolled
integrator — `strip.flick(velocity, 0)` drives arrow keys (one item's
worth of computed velocity via `v = sqrt(2 * flickDeceleration *
distance)`), click-to-jump, and wheel input (`WheelHandler` accumulates
into `strip.horizontalVelocity` so rapid notches build real momentum
instead of each notch being an isolated step) through the same
`_flickToIndex`/`_wheelImpulse` β†’ `strip.flick()` path — one motion
system for all three input methods, as the brief asked for. Drag-to-
scroll works for free via `Flickable`'s own default interactivity.

Per-delegate coverflow depth: center-distance is now a continuous real
number derived from `delegate.x`/`strip.contentX` (not the old integer
`index - currentIndex`), driving `scale`/`opacity` and a Y-axis 3D
`Rotation` (`axis {x:0;y:1;z:0}`, clamped Β±32Β°) so neighbors visibly
recede rather than just shrinking flat. A `SpringAnimation` corrects
`strip.contentX` to the exact centered position on `movementEnded`
(`spring: 2.8, damping: 0.35`) — this is also what gives the subtle
overshoot-settle "record crate" feel, most visible on wheel/drag flicks
since arrow-key/click flicks already land almost exactly on target from
the velocity formula.

**highlightRangeMode: StrictlyEnforceRange was dropped.** The scaffold
combined it with `snapMode: SnapOneItem`; under polish it turned out
`StrictlyEnforceRange`'s own range-enforcement fights a programmatic
`strip.flick()` call outright — flicking did nothing visible and
`currentIndex` never moved, because the range enforcement isn't wired to
participate in a `flick()`-driven move the way it is for a real drag
gesture. Replaced with `snapMode: NoSnap` + manual `leftMargin`/
`rightMargin` (so first/last items can still center) + `currentIndex`
tracked by hand off `contentX` via `indexAt()` in `onContentXChanged`.
This is a real, if less-documented, pattern for exactly this
coverflow-via-ListView shape.

**A second, nastier bug found only by testing, not review:** the first
working version of `_flickToIndex`/`_wheelImpulse` computed velocity
sign as `direction * speed` (positive direction = next item = positive
velocity) — looked correct on paper. It wasn't: `Flickable.flick()`'s
velocity sign is the *gesture* velocity, not the content-position
delta, so it's inverted relative to "which way contentX should move."
The bug was silent and total: from the first wallpaper (already at the
left boundary), Right-arrow computed a positive velocity that tried to
push `contentX` further past the boundary it was already sitting at,
and `boundsBehavior: DragOverBounds` correctly rejected the overshoot —
net result, zero visible motion and zero state change, no QML error to
point at it. Left then also silently no-op'd (target index -1 clamps to
0, `deltaItems === 0`, early return). Caught by testing both directions
from the edge and noticing *neither* had any effect, not by re-reading
the code. Fixed by negating: `strip.flick(-direction * ..., 0)`.
**Take-away for this file specifically:** any future change to the
`_flickToIndex`/`_wheelImpulse` velocity math needs a live from-index-0
Right-arrow test, not just a code read — the failure mode is silent.

**Concurrent-edit note:** this polish pass was picked up mid-stream from
a separate, unrelated interactive session (`aphotic-hypr-b2`) that had
independently started the same task on the same machine and left the
file mid-debug (temporary `console.log` diagnostics, an abandoned
hardcoded `strip.flick(3000, 0)` test in `Keys.onRightPressed`, dead
`preferredHighlightBegin`/`End` left over from the range-mode it had
already moved away from). That instrumentation has been fully removed;
the `NoSnap` + manual-`currentIndex` architecture it landed on was kept
because it's the correct fix for the `StrictlyEnforceRange`-vs-`flick()`
conflict above.

**Verified live** (via `wtype` + `theme.json` state diffing + `grim`
screenshots, no QML errors in `qs -c aphotic log` through any of this):
open/center on the active wallpaper, Right/Left arrow-key flick in both
directions with correct settle, Escape-revert to the pre-open wallpaper,
Enter-commit leaving the live-applied wallpaper in place, picker
open/close via `hyprctl layers`.

**Not verified by simulation** (no scroll-wheel or pointer-drag
simulation tool exists in this environment, same limitation noted
elsewhere this session): `_wheelImpulse`'s momentum accumulation feel,
drag-to-scroll, click-to-jump on a non-center delegate, click-to-commit
on the center delegate, and the `DragOverBounds` rubber-band feel at the
list's edges. These are code-reviewed only — the wheel/drag velocity
sign convention was derived the same way the arrow-key one was, and that
one was wrong until tested, so treat this as a real gap, not a
formality, until someone flicks it with an actual mouse/trackpad.

**Scope note:** the polish brief mentioned "theme selector and randomize
control (from the prior scope addition)" as existing UI to restyle.
Neither exists in this component — the picker is still exactly
`WallpaperPickerWindow.qml` + `WallpaperFilmstrip.qml`, no controls
beyond the filmstrip/label/counter. Not added here either, since the
brief was explicit this pass is refinement of what's already built, not
new scope.

**Status:** motion/visual polish complete for the interactions that
could be verified live. Wheel and drag paths need a real mouse pass
before calling this done-done.

---

## Next up

Nothing queued right now beyond the wallpaper picker above. See
`docs/LEDGER.md` for active bugs/gaps and the queued-next list,
`docs/ROADMAP.md` for the longer-lived backlog, or `docs/IDEAS.md` for
unreviewed/uncommitted feature ideas.

---

**The old "Corrections to `docs/ROADMAP.md` and `docs/IDEAS.md`" and
"Dead code and stubs found in passing" sections that used to be here
have moved to `docs/LEDGER.md`** (2026-08-28 consolidation pass) — that
doc is now the one place tracking untracked/half-implemented/uncorrected
items across the whole project, rather than splitting them between this
file's tail and wherever else. The `ROADMAP.md`/`IDEAS.md` corrections
listed there are still **not yet folded into those two docs** — that
remains true, just tracked in one place now instead of two.
