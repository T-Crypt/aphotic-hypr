# In Flight

Working queue for the current push. `docs/ROADMAP.md` is the long-lived
backlog; this file is the short-lived one — what is being worked on right
now, what was just finished and why it was done that way, and what the
next agent or session should pick up.

Anything that lands and stops moving gets folded into `ROADMAP.md`'s
Shipped section and deleted from here.

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

## Next up

Ordered by value per unit of effort. Items 1–3 are small and independent;
4–5 are the ones that matter most for a public release.

### 1. `Toaster.toast()` is an empty function with five live callers — S
`services/Toaster.qml:9` is `function toast(...): void {}`. Its comment says
notifications "aren't vendored in Phase 1", but they shipped
(`services/Notifs.qml`, `modules/notifications/`). Callers that silently do
nothing today: `modules/bar/popouts/NetworkPopout.qml:79` (clicking a
password-protected Wi-Fi network gives *no* feedback at all),
`services/Audio.qml:134,146` (the only feedback the `SUPER+CTRL+O`
output-cycle keybind has), `services/Players.qml:62`. Six other call sites
in this repo already shell out to `notify-send` (`Pomodoro.qml:52`,
`PkgSearch.qml:124`, `HostInfoStatus.qml:31`, `EyedropperPicker.qml:68`,
`Picker.qml:104`, `Wallpapers.qml:77`) — follow that pattern. Highest
value-per-line in the tree.

### 2. Grid launcher has no keyboard navigation — S
Shipped 2026-08-28, mouse-only. `modules/launcher/Launcher.qml:196-206`:
`Keys.onReturnPressed` reads `list.currentItem` and `Keys.onDown/UpPressed`
drive `list` — but in Grid style `list` is `visible: false` (`:365`) while
`grid` (`:396-428`) holds the visible highlight. Arrows move an invisible
cursor and Enter always launches list index 0. `AppGridItem.qml` has no
`execute()`. First thing anyone trying the newly advertised feature hits.

### 3. `services/Colours.qml` is a generated file tracked in git — S
`Configs/wallust/wallust.toml` templates it to
`~/.config/quickshell/aphotic/services/Colours.qml`, and that directory is
a symlink into the repo — so **every theme or wallpaper switch rewrites a
tracked source file**. It is dirty in the working tree right now for
exactly this reason, and it is not in `.gitignore`. Any public user running
`aphotic update` (which does `git pull`) gets a checkout conflict against
machine state. Needs a decision, not just an ignore rule: the committed
copy is also the fallback palette, so the fix is probably to template to a
separate generated file that `Colours.qml` reads, leaving the tracked file
static. Touches `.gitignore`, `Configs/wallust/wallust.toml`,
`tests/test_repo_layout.sh`.

### 4. Uniform `toggle(<name>)` IPC dispatcher — S/M
18 `IpcHandler` targets exist. Ten are already pure `toggle()` and are
near-identical boilerplate — `shell.qml:175` (launcher), `:194` (session),
`:204` (dashboard), `:214` (agent), `:224` (settings), `:234`
(intelligence), `:244` (dnd), `:252` (notifications), `:262` (pkginstall),
and `ColorPicker.qml:50` — each doing `focusedInstance(...)` plus flipping
one `ScreenState` bool. Collapse them into one
`IpcHandler { target: "aphotic"; function toggle(name) }` backed by a
name → state-key map, keeping the existing targets as thin aliases for
back-compat. Leave the eight verb-bearing targets alone (`mpris`,
`brightness`, `picker`, `lock`, `hypr`, `audio`, `notifs`, `bar`). Call
sites to update: 25 in `Configs/hypr/keybinds.lua`, plus
`Configs/.local/lib/aphotic/commands/cmd_bar.sh`, `cmd_shell.sh`,
`scripts/showcase/run_demo.sh`, `docs/cli.md`. Worth doing *before* more
surfaces land, since every new one then becomes bindable with no new
plumbing.

### 5. In-launcher Settings search — S/M
Everything needed already exists: the 15-entry category index at
`modules/settings/SettingsPanel.qml:28-43` (each with `label` +
`description` — exactly the keyword corpus), the prefix-mode dispatch at
`modules/launcher/Launcher.qml:49-62` with its model switch (`:257-296`)
and delegate switch (`:317-392`), and a precedent for cross-surface jumps
(`ScreenState.qml:24-28`'s `launcherPrefill`). Work: hoist `categories` out
of `SettingsPanel.qml` into `config/` or a singleton, add
`ScreenState.settingsCategory`, add a `SettingsItem.qml` delegate, and pick
a prefix (materially cheaper than interleaving heterogeneous results into
the apps list). A 15-pane Settings menu is undiscoverable without it.

---

## Corrections to `docs/ROADMAP.md` and `docs/IDEAS.md`

Verified against the tree; fold these in when those files are next touched.

- **Calendar applet is already shipped.** `IDEAS.md` lists it as "not
  currently in Aphotic"; `modules/dashboard/DashCalendar.qml` is a full
  month grid referenced from `DashboardTab.qml`, `Clock.qml` and
  `SettingsPopout.qml`.
- **Dashboard tabs are already shipped.** `ROADMAP.md`'s "Organize the
  Dashboard into real tabs" is stale —
  `modules/dashboard/DashboardContent.qml:14-19` defines the five tabs and
  `:59-98` is the Loader-per-tab cross-fade the design doc specified.
- **The keybinds cheatsheet is not cheap.** `IDEAS.md` assumes
  `Configs/hypr/keybinds.lua` is "one Lua table to read". It is not — it is
  a sequence of imperative `hl.bind(...)` calls with keys built by string
  concatenation, actions as opaque `hl.dsp.*` calls, and a `for i = 1, 10`
  loop generating 20 binds at runtime. Build it on `hyprctl binds -j` at
  runtime instead, which is both cheaper *and* correct for users who edited
  their own binds.
- **Calculator applet conflicts with a stated non-goal.** `README.md:150`
  lists a calculator among things deliberately left out. Reconcile before
  building it.
- **Dock/Minimal parity is worse than "no popouts".** Picking either style
  also silently deletes the battery, network, bluetooth and VPN indicators
  (`DockBar.qml:207-215`, `MinimalBar.qml:62-85`,
  `MinimalIndicators.qml:23-29` ships one icon), and Dock additionally has
  no `handleWheel`, so it loses scroll-to-volume. Both styles are
  advertised with screenshots and live previews. Split the roadmap item:
  status-icon parity is a medium lift, popouts are a large one (the flyout
  geometry in `popouts/Wrapper.qml` assumes an edge-docked strip, so a
  floating centered pill needs new positioning math).

## Dead code and stubs found in passing

Not fixed here; each is a small independent cleanup.

- `services/AgentProviders.qml:151` — `liveSessions` is recomputed from
  `ls` every 5s and read by nothing. Meanwhile
  `Configs/.local/lib/aphotic/agent_hook.sh:30` writes
  `{event, tool, updatedAt}` per session that is never parsed. The Claude
  Code hook does real work on every tool call for zero effect. This is the
  exact dependency `ROADMAP.md` says plugin `on_agent_event` is blocked on.
- `Configs/.local/lib/aphotic/commands/cmd_scheme.sh:29` — writes
  `scheme.active`, which has no consumer anywhere. `docs/cli.md:18`
  advertises this command as done.
- `docs/cli.md:12` — calls `aphotic shell` a stub because "IPC passthrough
  needs real IPC targets". There are 18.
- `Configs/.local/lib/aphotic/commands/cmd_ai.sh:39` and `cmd_iso.sh:28-32`
  — both print a literal `TODO` to the user's terminal.
- `components/ScreenState.qml:13-14` — `utilities` and `sidebar` are
  declared, referenced nowhere, and persisted to disk.
- `components/AnchorAnim.qml`, `components/AnimLoader.qml`,
  `components/effects/Elevation.qml` — instantiated nowhere;
  `Elevation.qml` is still exported by `components/effects/qmldir`.
