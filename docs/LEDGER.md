# Ledger

Single unified tracking log for Aphotic-Hypr. Replaces the old pattern of
several parallel working docs (`IN_FLIGHT.md`'s own session-log style,
plus scattered "known gap" sections at the bottom of feature docs) with
one place that answers three questions for anyone picking up the repo:

1. What's actively in flight right now?
2. What's shipped-but-has-a-known-gap (half-implemented, not keybound,
   not documented, not verified live)?
3. What's queued next?

`docs/ROADMAP.md` stays the longer-lived feature backlog (bigger,
undated items). `docs/IDEAS.md` stays the raw idea-capture/triage doc.
`docs/CHANGELOG.md` stays the shipped-history log. `docs/
AGENT_TRACKING.md` and `docs/PLUGIN_SYSTEM.md` stay as living design
docs for those two subsystems specifically, since they're referenced by
name elsewhere. Everything else that used to be scattered across
`docs/IN_FLIGHT.md`'s corrections/gaps sections now lives here instead.

**Retired to `docs/wiki-pending/` (2026-08-28):** `cli.md`, `bar-styles.md`,
`exploit-layer.md`, `terminal_games.md`, `COMMAND_CENTER.md`. These are
reference/how-to material, not tracking docs — they'll be migrated into a
real Wiki once that's stood up. Kept on disk (gitignored `docs/`, so no
history is lost either way) rather than deleted, so nothing has to be
reconstructed from memory when the Wiki work starts. Do not edit them in
place until then; if something in one goes stale before the Wiki exists,
note it here instead.

---

## Fixed 2026-08-29 (late): Dock was almost entirely dead to pointer input — anchors collapsed its input region to a 72x72 square

**Confirmed fixed by the user.** One fault caused all four reported
symptoms on the `dock` bar style: the hover highlight not tracking the
mouse, not all icons highlighting, icons not responding to clicks, and
the Calendar/Time pill not opening the Dashboard.

### The fix

`modules/bar/DockWindow.qml`: **removed all six of `dockBar`'s anchor
lines and replaced them with plain `x`/`y`/`width`/`height` bindings** —
the same pattern (and the same reasoning) `BarWindow.qml` already uses
for `barWrapper`, and which that file already documents. That is the
whole change.

### Root cause

`DockWindow.qml` masks its layer surface to its content with
`mask: Region { item: dockBar }`, so **dockBar's bounds ARE the dock's
entire Wayland pointer-input region.** With the six anchor lines it
carried (each a `cond ? parent.X : undefined` ternary), the live
instance measured:

    dockBar = 72x72   while   implicit = 674x56.8

72 is this window's own `reservedThickness` — its THIN axis — applied to
BOTH axes. So only a 72px square in the middle of a 674px-wide pill
accepted pointer input. Everything else received no events at all,
neither hover nor clicks. The pill still PAINTED at full size, because
it is `anchors.centerIn: parent` and simply rendered outside its own
parent's bounds (at `x: -301`) — which is why the dock looked perfect in
every screenshot while most of it was dead.

The anchors misbehave for the reason `BarWrapper.qml` documents at
length: **assigning `undefined` to an anchor does not reliably CLEAR a
previously-bound anchor line.** Settings load asynchronously, so this
window starts in the QML defaults (vertical, left-docked) and then flips
to the user's persisted orientation, leaving first-state anchors bound
alongside second-state ones. Two opposing anchors on one axis make Qt
derive that axis's size from the span between them.

### The wrong turn, recorded because it cost the most

**An earlier attempt added `width: implicitWidth` / `height:
implicitHeight` to `dockBar` while LEAVING THE ANCHORS IN PLACE. It
changed nothing** — re-measured at 72x72 afterwards. An anchor-driven
size overrides an explicit width/height binding outright; you cannot
paper over a bad anchor with an explicit size. Only removing the anchors
works. This was shipped and declared fixed on the strength of two
cropped screenshots that appeared to show a hover highlight, and the
user correctly rejected it.

**Two process lessons, both earned expensively here:**
1. **Screenshots validate paint, never input — and never motion.** The
   dock rendered pixel-perfect while being dead to the pointer. A faint
   difference between two still frames also cannot show whether an
   animated highlight *glides*; `HoverPill` animates `centerAlong`, and
   only a real hover sweep or a log probe can confirm that.
2. **When a Quickshell window masks to an item, measure that item's
   actual `width`/`height` against its `implicitWidth`/`implicitHeight`
   FIRST**, before theorising about hover logic. Every hypothesis
   pursued before that one measurement — `MultiEffect` layer offsetting
   input, `MouseArea` hover starvation from nested handlers, `BarHit`
   hit-test drift, missing `checkPopout` plumbing — was wrong, and all
   were plausible from code review alone.

### How it was verified

Objective log probes on the running shell, not screenshots. Before the
fix, a scripted cursor sweep across the whole dock
(`hyprctl dispatch 'hl.dsp.cursor.move({x=X,y=Y})'`) produced hover
events from **exactly one element** — the single `StatusIcons` group
whose scene rect (`x=1693..1801`) overlapped the live 72px mask
(`x=1684..1756`). The app icons, workspace dots, clock `StateLayer` and
the other two status groups logged **nothing at all**. After the fix the
same sweep logs `APPICON hover=true Firefox`, `WS hovered=<dot>` and
`CLOCK hover=true`, and `dockBar` measures `674x56.8` at `x=1383`.
User confirmed the fix by hand.

### Still open (unchanged by this fix)

- **Dock still has no popout system** (`checkPopout` / popout
  positioning). Tray menus and status-icon hover flyouts still do not
  open on Dock. Tracked in `docs/ROADMAP.md`'s Bar section.
- **Only bottom-docked horizontal was measured.** The new x/y bindings
  cover all four orientations explicitly, but top-docked horizontal and
  left/right vertical have not been re-swept on a real display.
- `MinimalBar.qml`'s `checkPopout` is still a literal empty no-op.

### Tooling note — corrects the earlier `ydotool` entry below

**`ydotool` pointer BUTTON events do not work on this machine, even
though motion does.** `ydotool mousemove` (relative) moves the cursor
fine but accelerated (~1.83x), so `-a` absolute coordinates are
unreliable — **the "coordinates are 2x" rule recorded further down does
not reproduce.** `ydotool click 0xC0` has no effect whatsoever:
confirmed by clicking inside a `kitty` window with the cursor verified
over it via `hyprctl cursorpos` and watching `hyprctl activewindow` not
change. `/tmp/ydotoold.log` contains `sudo: a password is required`, so
the running `ydotoold` is likely not fully privileged.

**Use `hyprctl dispatch 'hl.dsp.cursor.move({x=X,y=Y})'` for cursor
positioning** — exact, no daemon, and what this investigation used.
There is currently **no working way to synthesize a click** here;
anything click-gated still needs the user.

## Hardware context (2026-08-28)

System moved from the dev VM to real hardware: **RTX 4090 + i9-14900K**.
The dev VM is still reachable at `10.0.0.26` for anything that still
needs a clean-room comparison, but active work now happens on bare
metal. This matters for this ledger specifically because two of the
bugs below (GPU temp, GPU misdetection) were latent on the VM — no
discrete GPU to trigger them — and only surfaced now.

---

## Fixed this session (2026-08-28)

### 1. Dashboard Performance tab: wrong GPU, no temp, NVIDIA/AMD/Intel support
**Symptom reported:** Performance tab didn't report CPU/system temp, and
showed the wrong GPU (Intel iGPU instead of the installed RTX 4090).

**Root causes found (three independent bugs, not one):**
- `services/SystemUsage.qml`'s GPU vendor-ranking regex was
  `/amd|ati/i` with no word boundary — this matches the substring "ati"
  inside "Corporation", which **every** `lspci` vendor string ends with
  (`"Intel Corporation"`, `"NVIDIA Corporation"`, etc.). Every vendor
  therefore ranked as "AMD-or-better," the comparator was a no-op, and
  the first-listed PCI entry (always the iGPU — lower bus number) won
  regardless of what discrete GPU was present. Reproduced outside QML
  (Python re-implementation of the same regex) before fixing, not just
  inferred from a code read. Fixed with a word-boundaried
  `/\b(amd|ati)\b/i`.
- `install.sh`'s `install_nvidia_driver()` only installed
  `nvidia-open-dkms` (the kernel driver) — never `nvidia-utils`, the
  package that actually provides the `nvidia-smi` binary the Performance
  tab's NVIDIA stats query shells out to. On a fresh real-hardware
  install, `nvidia-smi` simply isn't on disk and the query fails
  silently. Fixed: `install_nvidia_driver()` now also installs
  `nvidia-utils`.
- CPU temp read a hardcoded `/sys/class/thermal/thermal_zone0/temp` —
  which chip claims zone 0 is ACPI registration-order dependent, not
  reliably the CPU package sensor on every board. Fixed to prefer
  `sensors -j` (parses `coretemp`'s "Package id 0" on Intel,
  `k10temp`/`zenpower`'s "Tctl"/"Tdie" on AMD), falling back to the old
  thermal_zone0 path only when lm-sensors isn't installed. `lm_sensors`
  added to both `profiles/base/full.toml` and `minimal.toml`'s `prep`
  list so it's present on every install, not just this machine (it
  already happened to be installed here).

**Also fixed while in here:**
- `Dashboard.qml`'s placeholder-visibility check referenced
  `SystemUsage.gpuType`, a property that has never existed on
  `SystemUsage.qml` (only `gpuDetected`/`gpuName`/etc.) — dead code,
  caught by grep, corrected to `gpuDetected`. Did not affect the main
  GPU card, only the "hide everything" empty-state check.
- AMD and Intel GPU temp were previously **not implemented at all** —
  `gpuStatsProc`'s `default` branch was a no-op (`["true"]`), so any
  AMD or Intel-only machine always showed "N/A" regardless of what was
  installed. Added real hwmon-based temp reads for both
  (`/sys/class/drm/card*/device/hwmon/hwmon*/temp1_input`), and a best-
  effort `intel_gpu_top`-based usage read for Intel (falls back to
  temp-only if `intel_gpu_top` isn't installed or needs privileges this
  process doesn't have).

**Scope addition requested mid-fix:** a GPU selector, since a machine
with both an iGPU and a discrete GPU has two real monitoring targets,
not one. `SystemUsage.qml` was restructured around a `gpus: var[]`
array (every `lspci`-detected controller, each with its own polled
`vendor`/`name`/`statsAvailable`/`perc`/`temp`) plus
`selectedGpuIndex`/`selectGpu(index)`/`selectedGpu`, with the existing
`gpuName`/`gpuPerc`/`gpuTemp`/`gpuStatsAvailable`/`gpuDetected`
properties kept as read-only passthroughs to whichever GPU is selected
— so `Dashboard.qml`'s card needed almost no changes. A small
swap-horizontal icon button (`GpuCycleButton`, new component in
`Dashboard.qml`) appears in the GPU card's header **only when more than
one GPU was detected** (`SystemUsage.gpus.length > 1`), cycling through
them on click. `CardHeader`/`HeroCard` both gained a `trailingItem`/
`headerTrailingItem` passthrough property to support this without
every other card needing to know about it.

**Verified live** on the real RTX 4090 + i9-14900K box: `nvidia-smi` and
`sensors -j` both confirmed installed and returning correct data before
the fix; after the fix, the Performance tab correctly shows "GPU - AD102
[GeForce RT..." at real live usage/temp (71%/26°C at time of test) and
the CPU card shows the real coretemp Package-id-0 reading (61°C under
light load). The cycle button renders in the GPU card header. **Not
verified live:** actually clicking the cycle button and confirming it
switches to the Intel iGPU's own stats — no pointer-simulation tool
exists in this environment (`wtype`/`ydotool`/`dotool`/`wlrctl`/
`xdotool` all confirmed absent, `/dev/uinput` exists but no Python
`uinput`/`evdev` binding is installed either) — this is the same
environment limitation `IN_FLIGHT.md` already documented for hover/
right-click testing. The selection/cycle logic was verified by code
inspection only.

**A real process bug caught and fixed while verifying this fix, worth
flagging for whoever next debugs "my QML edit didn't take effect":**
`~/.config/quickshell/aphotic` (what `qs -c aphotic` actually loads) is
a **deployed copy**, not a symlink back to this repo — `restore.manifest`
confirms `quickshell/aphotic|~/.config/quickshell/aphotic` is a real
directory copy, populated by `aphotic restore`. Editing files under
`Configs/quickshell/aphotic/` in this repo and running `aphotic reload`
does **nothing** until the edited files are also copied to
`~/.config/quickshell/aphotic` — `aphotic reload` only restarts the
daemon, it doesn't re-sync from the repo. This cost real time this
session: several rounds of "reload, screenshot, still looks unfixed"
were actually testing stale pre-edit code. **Whoever next does live QML
editing in a dev checkout of this repo should either work directly in
`~/.config/quickshell/aphotic` and diff back to the repo when done, or
explicitly `cp`/rsync after every edit before reloading** — there's no
existing "sync my repo checkout to the live config" command; the
closest is `aphotic restore --overwrite`, which auto-snapshots first but
is a full-tree overwrite, not a targeted file sync, and wasn't used here
to avoid clobbering unrelated live state.

**Second real bug caught only by the daemon crashing:** the first
version of the multi-GPU rewrite above used JS object-spread
(`{...gpu, statsAvailable: false}`) inside `gpuStatsProc`'s result
handler. Quickshell's QML JS engine does **not** support object-spread
syntax — this is not a hypothetical, it took the whole shell down
(`Unexpected token '...'`, every dependent singleton failed to load,
`aphotic-shell.service` hit `start-limit-hit` after 5 rapid crash-
restarts). Call-site spread (`Math.max(...arr)`, pre-existing elsewhere
in `Dashboard.qml`) does work — only object-literal spread doesn't.
Fixed by building the updated record field-by-field. **Take-away:**
after any `aphotic reload`, check `systemctl --user status
aphotic-shell.service` (not just "did the command print ok") — the
restart can silently fail and fall back to a stale already-running
instance, which is exactly what made this look fixed for a few rounds
of testing when it wasn't.

---

### 2. Settings → Launcher pane: off-center layout
**Symptom reported:** the Launcher settings tab (Grid/List picker) looked
oddly placed, not centered — because it's a one-control pane using the
same top-anchored `ColumnLayout` pattern every denser pane (3+ sections)
uses.

**Root cause:** `SettingsPanel.qml` stretches every pane's root item to
fill the full available pane height (`Math.max(paneFlick.height,
implicitHeight)`). Panes with enough content fill that space naturally;
`LauncherPane.qml` has only a title + one `SettingsGroup` row, leaving
~400px of dead space below it — a content-density problem, not a wrong-
anchor bug. No sibling pane needed vertical centering because no sibling
pane is this sparse.

**Fix:** `modules/settings/panes/LauncherPane.qml` — added a
`Layout.fillHeight: true` spacer `Item` above and below the title+group
block, so it centers as a unit in whatever height the pane host hands
it. No anchors/margins touched, no other pane's pattern affected.

**Verified:** no QML errors after reload. **Not verified visually** —
reaching this specific settings pane requires either a real click or the
launcher's `?` settings-search-and-jump flow, both needing pointer/
keyboard simulation this environment doesn't have (see the GPU section
above for the same limitation). Worth a real look next time this pane
is opened by hand.

---

### 3. Bar: "right click for options" on the Spotify/media icon does nothing
**This bug does not exist as reported — the premise was a mixup, not
half-implemented wiring.** Confirmed exhaustively (single grep hit
across the whole repo): the string "right click for options" lives in
`TrayPopout.qml:34`, describing the **system tray** icon cluster, not
Media. `Media.qml` has no such hint anywhere and never has.

Tray's right-click is fully implemented and working:
`TrayItem.qml:15` sets `acceptedButtons: Qt.LeftButton |
Qt.RightButton`, dispatching `activate()` on left and
`secondaryActivate()` (the SNI item's own native context menu) on
right. Nothing to fix here.

**Likely source of the confusion:** Tray and Media sit adjacent in the
bar (`Bar.qml` lines ~470/478) — the tray's hover hint was probably seen
near the media widget and misattributed to it.

**If real right-click options on Media are wanted, that's new scope, not
a bug fix** — logged below under "Queued / open."

---

### 4. Bar popouts: long hover intermittently stops updating/disappears (2026-08-28)
**Symptom reported:** hovering a bar icon for a while sometimes stops
popout animations from triggering — either a new popout fails to appear,
or an open one drops out from under the cursor while it's still being
hovered.

**Investigated against `caelestia-dots/shell`'s own
`modules/bar/popouts/` implementation** (fetched live via `gh api`, not
assumed from memory) as the user asked. Caelestia's actual bar/popout
architecture has moved on structurally (a detach/"nexus" model,
`PopoutState` singleton) and isn't a drop-in file-for-file match anymore
— but its `Bar.qml checkPopout` revealed the actually-relevant
difference: **caelestia never clears `hasCurrent` on a sub-target miss
within an already-matched entry.** Its `statusIcons`/`tray` branches only
ever set `hasCurrent = true` on a real match; a miss just leaves
whatever was already showing alone. Aphotic's equivalent branches did
the opposite — an explicit `else { hasCurrent = false }` on every miss,
including a miss against a *sub*-target (which pill, which tray index)
while the pointer was still squarely over the *same bar entry* the whole
time.

**Root cause:** `HoverHandler.onPointChanged`-driven re-evaluation calls
`checkPopout(pos)` on every pointer sample. A long, nearly-still hover
gets fewer fresh samples, so any single borderline one — landing in the
seam between two status-icon pills, between two tray icons, or right at
a `contains()` rounding edge — has outsized odds of being the sample
that actually fires, and it fell straight into the `else` branch and
blanked the popout even though the cursor never left the entry. Separately,
`Wrapper.qml`'s `flyoutHover.onHoveredChanged` closed the popout the
instant `hovered` went false with zero debounce — `QQuickHoverHandler.
hovered` can flicker false-then-true within a frame or two right at a
rounded corner (the flyout's own radius) or while its own width/height
`Behavior`s are still resizing the geometry the handler tracks.

**Fix — region-hysteresis lock, following caelestia's "don't clear on a
sub-match miss" model:**
- `Bar.qml`: added `_lockedEntry`/`withinLockedRegion()` — once a popout
  is open for a bar entry, `checkPopout` stays locked on that entry as
  long as the pointer is still within its bounds (4px margin), and only
  falls through to a fresh nearest-match once the pointer genuinely
  leaves. The `statusIcons`/`tray` sub-match-miss branches now only clear
  `hasCurrent` on **fresh arrival** at an entry, not on a borderline miss
  while re-evaluating the same already-locked entry.
- `TaskbarBar.qml`: identical fix, duplicated by hand — this file already
  hand-copies `Bar.qml`'s hit-testing logic (documented in an existing
  comment as "a copy, not a shared function"), so the bug and the fix
  both had to be duplicated. Not currently the active style
  (`barSkin: "pill"` → `"full"` on this machine today) but the user has
  tried Taskbar/Dock/Minimal before (`barStyleDefaultsApplied` in
  `settings.json`), so it was in scope for "review the popouts," not
  speculative.
- `popouts/Wrapper.qml`: `flyoutHover`'s leave is now debounced through a
  60ms `Timer` (`flyoutHoverExitTimer`) instead of closing instantly —
  absorbs a same-frame flicker without making a genuine leave feel
  laggy to close.

**Not touched:** `DockBar.qml`/`MinimalBar.qml` have no popout system at
all (`docs/ROADMAP.md`'s existing Bar section already tracks this as a
real feature gap, not something this pass introduced or was asked to
fix).

**Verified:** clean reload, no QML errors, in both `Bar.qml`'s "full"
style (the currently active one) and `TaskbarBar.qml`. **Not verified
live against the actual reported symptom** — reproducing "hover
motionless for N seconds near a pill/tray boundary" needs a held,
still pointer position this environment's lack of pointer-simulation
tooling (see "Verification notes" below) can't script. The fix is a
direct structural port of caelestia's own "don't clear on sub-match
miss" behavior plus a standard hover-debounce pattern, not a guess —
but treat this as **code-reviewed, not reproduced-then-fixed**, and
give it a real long-hover test at the desk before calling it closed.

### 4b. Follow-up, same day: two more root causes found after user re-report
The fix above wasn't enough — user re-tested and reported it's still hard
to actually *reach* a popout (concrete case: the network icon's Wi-Fi
list), with a new symptom: "hover off and back too soon" sometimes leaves
the bar icon highlighted but shows no popout at all. Investigated
further rather than assumed fixed. Two more real, independent bugs found:

**Bug A — duplicate, racing hover pipelines (explains "highlights but no
popout").** `StatusIcons.qml`'s per-pill `HoverPill` highlight is driven
by its own local `HoverHandler` (`pillHover`, computing `hoveredEntry`
via `BarHit.nearestAt`) — a completely separate event stream from
`BarWrapper.qml`'s single outer `HoverHandler` that drives `checkPopout`.
Two independent handlers computing "which icon is under the cursor" from
two unrelated Qt event streams have no guaranteed ordering — right after
a fast leave-and-return, the pill's own local handler can register the
new icon a frame (or more) before/after the outer bar-level handler's
next `onPointChanged` tick, so the highlight and the popout can
genuinely disagree about what's currently hovered. **Fix:** `Bar.qml`
and `TaskbarBar.qml`'s `checkPopout` now read `matched.pill.hoveredEntry`
directly — the pill's own already-correct, zero-dead-zone result —
instead of re-deriving a second independent match via
`BarHit.nearestAlong`. One source of truth instead of two that can
drift. (`StatusIcons.qml`'s `groupContainers` comment updated to
document that `Bar.qml` now depends on `pill.hoveredEntry` staying live.)

**Bug B — the real one, a literal input dead zone (explains "can't get
to the popout fast enough").** `BarWindow.qml`'s `mask: Region` only
ever covered `barWrapper`'s own bounds plus the flyout's own (separately
masked) rect. The gap between them — `Tokens.spacing.small`, where the
flyout renders just off the bar's edge — was **never part of the
window's input-accepting area at all**. This isn't a race condition or a
missed event: a pointer crossing that gap literally leaves the
layer-shell surface, and the Wayland compositor treats that pixel strip
as click-through to whatever's on the desktop underneath. Zero hover
events of any kind are delivered while the cursor is in transit. This is
the actual mechanism behind "I can't get to the popout fast enough, it
goes away before I reach it" — it was never a timing problem to tune
away, the surface genuinely couldn't see the cursor there.

**Fix:** `popouts/Wrapper.qml` gained `bridgeItem` — an invisible `Item`
spanning exactly that gap (aligned to the flyout's own current
along-axis position/extent, on whichever cross-axis side the flyout
renders), with its own `HoverHandler` (`bridgeHover`) folded into
`hoveringFlyout`'s guard alongside `flyoutHover`. `BarWindow.qml`'s
`mask: Region` now includes a `Region { item: popouts.bridgeItem }`
alongside the existing flyout/agent-flyout regions, so hover tracking
(and thus `checkPopout`) is continuous from the bar strip straight
through the gap into the flyout — no more surface the cursor can fall
off of mid-transit. `bridge.width`/`.height` collapse to 0 automatically
when `flyout.width`/`.height` do (no content loaded), so this is a
real no-op — not just hidden — when no popout is open, and doesn't
absorb clicks meant for the desktop next to an unrelated icon.

**Verified:** clean reload, no QML errors, bar renders visually
unchanged (confirmed via screenshot — an invisible input region produces
no visual artifact, as expected), `hyprctl layers` confirms both bar
surfaces still valid post-reload. **Not verified against the literal
reported motion** (moving the cursor from the network icon into its
Wi-Fi list flyout fast) — same environment limitation as everywhere else
in this doc: no pointer-simulation tool exists here to script a real
cursor drag across the gap. This is the highest-confidence fix of the
three in this session (it addresses a mechanism that's provably true
from reading `BarWindow.qml`'s mask definition, not inferred from
symptoms), but it is still **code-reviewed, not reproduced-then-fixed
against the exact user-described motion** — worth confirming with a
real mouse before treating this as fully closed.

### 4c. Same day, second re-report: the bridge patch didn't fix it — the real fix was removing the gap entirely, plus a HoverHandler → MouseArea rewrite
User re-tested 4b's fix and reported it was unchanged, plus two new
symptoms: **directional failure** ("if I come from underneath [in
vertical bar mode] the popout doesn't appear, but coming from an
already-hovered Bluetooth icon first it works"), and **speed failure**
("if I scroll over them too fast... I'd expect them to pop up even if
it flies over"). Explicitly asked to go read caelestia's actual
`modules/bar/` source directly rather than reason from Aphotic's own
code, since the earlier fixes clearly weren't matching its real
behavior. Did that — fetched every relevant file via `gh api`
(`modules/drawers/ContentWindow.qml`, `Regions.qml`, `Panels.qml`,
`Interactions.qml`, `popouts/ClipWrapper.qml`) instead of re-reading
the previously-fetched `Bar.qml`/`Wrapper.qml`, which turned out to be
the wrong layer to compare against.

**Finding 1 — the "bridge" fix from 4b was solving the wrong problem.**
Caelestia's popout flyout has **zero gap** against the bar:
`popouts/ClipWrapper.qml`'s content sits at `anchors.leftMargin: 0`
against a parent that's itself flush against the bar
(`Panels.qml`: `anchors.leftMargin: bar.implicitWidth`). The `-
implicitWidth - 5` offset only applies while the popout is *hidden*
(sliding off behind the bar), never while shown. Aphotic's flyout had a
real `Tokens.spacing.small` gap between the bar and the flyout in EVERY
docking mode — bridging that gap (4b's `bridgeItem`) was a patch on a
design choice that shouldn't have existed. **Fixed properly:** removed
`Tokens.spacing.small` from `flyout`/`agentFlyout`'s cross-axis
position in `popouts/Wrapper.qml` — they now sit at exactly `root.
barWidth` (or the mirrored right/bottom-docked equivalent), flush
against the bar with no gap to fall into. 4b's `bridgeItem`/`bridgeHover`
and the corresponding `Region` in `BarWindow.qml`'s mask were reverted
outright — dead weight once there's no gap left to bridge.

**Finding 2 — the deeper architectural mismatch: `HoverHandler` vs.
`MouseArea`.** Caelestia's bar popout hover isn't driven by
`HoverHandler` (a `QQuickPointerHandler`) anywhere. It's a single
`MouseArea` (`modules/drawers/Interactions.qml`, `hoverEnabled: true`,
covering the *entire* window) calling `bar.checkPopout(y)` from
`onPositionChanged` on every native pointer-move event Qt delivers.
Aphotic used `HoverHandler` throughout (`BarWrapper.qml`'s outer
handler, `StatusIcons.qml`'s per-pill handler, `Wrapper.qml`'s flyout
handler) — a different, newer Qt Quick input mechanism with its own
event dispatch/coalescing path that does not behave identically to
`MouseArea` under Wayland. This is the most likely real explanation for
both new symptoms: a directional/positional miss on entry, and a
same-effect miss on fast movement — both are exactly the failure shape
of an event-coalescing difference (some pointer-motion samples get
dropped or merged before `onPointChanged` fires), not a logic bug in
`checkPopout` itself. All three of 4/4b's fixes (region-hysteresis,
duplicate-pipeline removal, gap-bridging) were built on the assumption
that `checkPopout` just needed to tolerate occasional missed/borderline
samples better — none of them addressed samples never arriving at all.

Presented this as an explicit scope decision (full rewrite vs. keep
patching `HoverHandler`) rather than deciding unilaterally, given the
size of the change; user chose the full rewrite.

**Fix — replaced every bar/popout `HoverHandler` with a `MouseArea`
(`acceptedButtons: Qt.NoButton`, `hoverEnabled: true`), matching
caelestia's mechanism exactly:**
- `BarWrapper.qml`: outer `hoverHandler` → `hoverArea`, driving
  `checkPopout`/`isHovered` from `onPositionChanged`/
  `onContainsMouseChanged` instead of `onPointChanged`/`onHoveredChanged`.
- `StatusIcons.qml`: per-pill `pillHover` converted the same way. Also
  fixed a second, independent bug found while rewriting it: the old
  `onPointChanged` handler was guarded by `if (!pillHover.hovered)
  return;` — redundant (the handler only ever fires while genuinely
  hovering) and actively harmful, since if the "entered" and first
  "point changed" signals didn't land in the order the guard assumed,
  the very first update was silently dropped, leaving `hoveredEntry`
  null until a second pointer sample arrived that a fast or
  entry-then-hold motion might never produce. This is a second, real,
  independent explanation for "highlights with no popout" beyond the
  duplicate-pipeline fix in 4b.
- `popouts/Wrapper.qml`: `flyoutHover` converted the same way, keeping
  4b's exit-debounce timer (still correct/useful independent of the
  `HoverHandler`→`MouseArea` swap).
- `acceptedButtons: Qt.NoButton` on all three preserves the original
  click-passthrough guarantee `HoverHandler`'s passivity used to
  provide — Qt's documented behavior is that a `MouseArea` accepting no
  buttons is transparent to press/release regardless of z-order, so
  none of this intercepts clicks meant for the bar's own icons or the
  popout content underneath.

**Verified:** clean reload, no QML errors, `journalctl` clean, bar
renders visually unchanged (screenshot confirmed — this is an input-
layer change with zero intended visual difference), config fully
synced to `~/.config/quickshell/aphotic`. **Still not verified against
the literal reported motions** (approaching a status pill from
underneath in vertical mode; a fast flick across multiple icons) — same
recurring environment limitation, no pointer-simulation tool exists
here. This is now the third pass at this bug; treat all of 4/4b/4c as
one connected investigation and verify all of it together with a real
mouse before considering the popout hover system settled, not just the
newest layer.

### 4d. 4c's MouseArea rewrite caused a real regression, plus the actual "from underneath" bug found
User reported almost immediately after 4c shipped: the hover-highlight
system was **gone entirely** across the bar — status-icon pills didn't
glow on hover, the workspace strip showed no hover indicator, "the
things previously implemented for highlights and active hover selection
are no longer there."

**Root cause:** 4c's `BarWrapper.qml` rewrite put a full-bar-covering
`MouseArea` (`hoverArea`, `hoverEnabled: true`) directly above
`Bar.qml`'s entire content tree. This was a real misunderstanding of Qt
Quick's input model, not a caelestia-fidelity issue: `HoverHandler` is a
*Pointer Handler*, explicitly designed to be one of several independent,
non-exclusive observers of the same pointer stream — many can coexist
stacked on top of each other and all still receive events. `MouseArea`
is the older, *exclusive* input primitive: a `MouseArea` with
`hoverEnabled: true` claims hover-move delivery for whatever's under the
cursor, and no other `MouseArea` beneath it in the same stack (however
deeply nested — `StatusIcons.qml`'s own pill `MouseArea`,
`Workspaces.qml`'s own workspace-hover `MouseArea`, every individual
status icon's own hover state) receives that motion at all.
`acceptedButtons: Qt.NoButton` only affects *click* passthrough, not
*hover* delivery — a real, distinct axis this session hadn't accounted
for. Concretely: 4c's outer `MouseArea` sat above everything and
silently starved every nested hover consumer in the bar.

**Fix:** `BarWrapper.qml`'s outer handler is back to `HoverHandler` —
reverted outright, not patched, since `MouseArea` is structurally wrong
at a layer with interactive children beneath it. This is why
`StatusIcons.qml`'s `pillHover` and `popouts/Wrapper.qml`'s
`flyoutHover` were safe to keep as `MouseArea`: both are declared
*before* (i.e. underneath, in z-order) the interactive content they
sit alongside (the pill's own icon `Repeater`, the popout content
`Loader`), so neither one intercepts anything above it. The outer
bar-covering layer is the one place in this tree where that ordering
trick isn't available, because there's nothing "underneath" it to stack
correctly against — it has to sit above the whole bar to track pointer
position across all of it.

**The actual "from underneath" bug, found while fixing the regression
above:** re-examining `Bar.qml`'s `checkPopout` after reverting to
`HoverHandler` surfaced why 4c's `matched.pill.hoveredEntry` read (the
duplicate-hover-pipeline fix from 4b) was itself fragile in a way 4b's
own testing never caught. Reading the pill's separately-maintained
`hoveredEntry` made popout resolution depend on TWO independently-timed
event streams agreeing: the outer `HoverHandler`'s own sample, and the
pill's local `MouseArea`'s own `hoveredEntry` update for that same
pointer position. On first entry into a pill — confirmed live via user
report, approaching a horizontal bar's status pill from directly
underneath (moving the cursor vertically up into the bar) — the outer
handler's sample can fire before the pill's own `MouseArea` has updated
`hoveredEntry` for that position, reading stale/null state and showing
no popout at all. Left-to-right movement mostly avoided this (the
pointer is usually already inside a pill's bounds by the time a
sample lands squarely on a new icon), which matches the user's own
observation that horizontal movement "seemed fine but not 100%
consistent." **Fixed:** `Bar.qml`/`TaskbarBar.qml`'s `checkPopout` now
computes the nearest-icon match directly and synchronously from its own
`pos` argument (`BarHit.nearestAlong` against `matched.icons`) again,
with no dependency on any other component's separately-timed state.
`pill.hoveredEntry` still exists and is still maintained by `pillHover`
— it now drives only the `HoverPill` glow, nothing else reads it.

**Known, accepted remaining limitation, not further fixed this pass:**
the outer `BarWrapper.qml` `HoverHandler` is a stock Qt Quick type with
its own event-coalescing behavior under fast pointer motion, and there
is no Quickshell-level knob to change that (checked: `HoverHandler`
isn't a Quickshell-custom type, nothing in quickshell-mirror/quickshell
alters its dispatch). A `MouseArea` can't be substituted at this
specific layer without repeating 4d's own regression, since it has
interactive children beneath it with no safe z-order trick available.
Some residual "very fast flick across many icons in one motion" misses
may remain for this structural reason — this is different in kind from
the bugs actually fixed in 4/4b/4c/4d (all of which were logic bugs
with deterministic root causes), and isn't something to keep
re-patching without a genuinely different mechanism (e.g. Quickshell
gaining a way to query raw compositor pointer-motion events at a higher
rate, which doesn't exist today).

**Verified:** clean reload, no QML errors, config synced, in both
`Bar.qml` and `TaskbarBar.qml`. **Still not independently verified with
a real mouse** — same recurring limitation. Given 4c caused a real,
user-visible regression that shipped without being caught before the
user tested it, treat every future change to this file tree with extra
suspicion: re-verify the hover highlight (pill glow, workspace
indicator) still works, not just the popout, after any further edit
here.

### 4e. Found the actual root cause of "the gap snaps the popout away" — a one-word typo, not a geometry or timing bug
User reported, precisely: "the SECOND the mouse hovers over the margin
gap between the BAR and the popout rendering, it snaps away. Doesn't
matter what configuration the bar is in." This was reported AFTER 4c's
zero-gap fix had already shipped, meaning the geometric gap fix from 4c
was not the real issue (or not the only one).

**Investigation, in order:**
1. Verified the zero-gap geometry from 4c genuinely has no gap: computed
   `root.barWidth` from the live config (`Settings.barInnerWidth *
   barCompact-factor + border padding` ≈ 57px for this machine's
   settings) and confirmed via `hyprctl layers` + a temporarily-forced
   `hasCurrent: true` test (reverted after) that the flyout's rendered
   position starts exactly at the bar's real edge with zero visible gap.
   This ruled out geometry as the cause.
2. Checked whether Quickshell's `Region` mask (`BarWindow.qml`) tracks
   an animated item's live geometry or only a stale snapshot, by reading
   `quickshell-mirror/quickshell`'s actual `region.cpp`/`region.hpp`
   source. Confirmed `PendingRegion::setItem` connects to the target
   item's `xChanged`/`yChanged`/`widthChanged`/`heightChanged` signals
   directly and rebuilds on every one -- the mask is NOT stale/lagging
   during the flyout's open/resize animation. Ruled out mask-lag as the
   cause.
3. With geometry and mask both cleared, looked at the actual state
   machine deciding when to close: `BarWrapper.qml`'s `hoverHandler`
   closes the popout when the bar itself loses hover, UNLESS
   `root.popouts.hoveringFlyout` is true (the guard meant to protect
   exactly the "moved from bar into flyout" case the user described).
   Traced `hoveringFlyout`'s definition in `popouts/Wrapper.qml`.

**The actual bug:** `hoveringFlyout` was defined as `flyoutHover.hovered`.
`flyoutHover` was converted from a `HoverHandler` to a `MouseArea` in
4c/4d's rewrite (see those entries) -- and `MouseArea` has no `hovered`
property, only `containsMouse`. This stale reference silently evaluated
to `undefined` (falsy) on every read, with no error anywhere (QML does
not throw on reading a nonexistent property, it just returns
`undefined`) -- so `hoveringFlyout` was **permanently `false`**
regardless of real cursor position. That made `BarWrapper.qml`'s guard
(`!root.popouts.hoveringFlyout`) **permanently `true`**, so the bar's
own hover-exit closed the popout unconditionally the instant the cursor
left the bar strip -- including when moving directly into, or already
sitting inside, the flyout. This is a complete, literal explanation for
the exact reported symptom: it reproduced on every single crossing
(not intermittently), in every bar orientation/position (nothing in
this code path branches on orientation), because the one guard that
existed specifically to prevent this had been silently broken by a
property-name mismatch left over from the `HoverHandler`→`MouseArea`
conversion two entries ago. **Fixed:** `flyoutHover.containsMouse`.

**Also fixed while auditing for the same mistake elsewhere:**
- Same file's `flyoutHoverExitTimer.onTriggered` had the identical typo
  (`flyoutHover.hovered`), also always-`undefined`/always-`true`.
  Functionally near-inert in practice (the timer is normally `stop()`'d
  before it can fire while genuinely still hovering), but real,
  incorrect code — fixed to `containsMouse` for correctness, not because
  it was reproduced as an independent cause.
- Audited every other `.hovered` reference across the entire
  `modules/bar/` tree (`grep`, not spot-checking) — everything else
  (`DockBar.qml`, `MinimalIndicators.qml`, `MinimalTray.qml`,
  `DockWorkspaces.qml`, `BarWrapper.qml`'s own `hoverHandler.hovered`)
  is a real, untouched `HoverHandler`, where `.hovered` is the correct
  property. No other instance of this mistake was found.
- Added a defensive `Qt.callLater()` defer around
  `BarWrapper.qml`'s own close-check (checking `hoveringFlyout` on the
  next event-loop tick rather than synchronously inside
  `onHoveredChanged`), since `hoverHandler` (bar) and `flyoutHover`
  (flyout) are independent hover trackers in separate component trees
  reacting to the same physical motion event when the cursor crosses
  the now-zero-width boundary between them — there's no language-level
  guarantee both handlers' updates for that one motion sample land in a
  particular order within the same tick. This is a real, if secondary,
  hardening on top of 4e's actual fix above, not the primary cause.

**Verified:** clean reload, no QML errors, config synced. **Still not
independently verified with a real mouse** — same recurring
environment limitation noted throughout this whole investigation. This
fix has meaningfully higher confidence than 4/4b/4c/4d's, though,
because it's a one-line dead-property-reference bug with a
deterministic, always-reproducing failure mode that exactly matches
every detail of the report (universal across configurations, happens
on the "second" of crossing, not intermittent) — not a
timing/coalescing theory that could only ever be partially confirmed.

### 4f. The real remaining bug — found and fixed with a live, instrumented, verified repro (not code review)
User re-tested 4e's fix and reported a new, more specific pattern:
coming down the vertical bar across the network and bluetooth icons
triggered nothing; only reaching the VPN icon triggered a popout;
going back up from VPN, the popout stayed showing (didn't update per
icon). Also asked directly what tooling could let this be verified
for real instead of continuing to guess from code and static
screenshots — a fair challenge, since 4/4b/4c/4d/4e were each shipped
on code-review confidence alone.

**Installed real verification tooling, with the user's help.** `ydotool`
(official Arch `extra` repo, not AUR) drives `/dev/uinput` directly via
a root-owned daemon (`ydotoold`) and works under Wayland with no X11
dependency — this lets a session script real, repeatable pointer
movement and screenshot the result, rather than reasoning about hover
behavior from static code alone. The user installed the package and
started the daemon (`sudo ydotoold --socket-own=1000:1000`, needed so
the daemon's Unix socket is writable by the non-root session actually
issuing `ydotool` commands). **Calibration finding, not assumed:**
`ydotool mousemove -a X Y` coordinates are NOT 1:1 with Hyprland's
logical pixel space on this machine — empirically probed (moved to
several known points, read back `hyprctl cursorpos`) and confirmed a
clean 2x scale factor (`ydotool` input × 2 = logical output) despite
both monitors reporting `scale: 1` in `hyprctl monitors`; the cause
wasn't chased further since the empirical factor is all that's needed
to drive it correctly.

**Real diagnosis, not more guessing:** added temporary `console.log`
instrumentation to the *deployed* `Bar.qml`'s `checkPopout` (never
committed to the repo — removed before this entry was written),
capturing the resolved entry, its live `x`/`y`/`width`/`height`, and
per-icon match results on every call. Scripted a `ydotool` sweep down
the vertical bar's status-icon column, in stages: a coarse 50px sweep
first to map the bar's actual live entry order (which turned out to be
`logo → workspaces → activeWindow → media → tray → clock → agent →
statusIcons → gap → settings → power`, confirmed against
`Config.qml`'s real default `entries.values`), then a fine ~8-10px
sweep specifically across the `statusIcons` entry's own bounds with
full per-icon logging.

**Root cause, confirmed from the captured data, not inferred:**
`BarHit.qml`'s shared `nearestAlong(container, pos)` — the ONE hit-test
function every bar style's `checkPopout` (`Bar.qml`, `TaskbarBar.qml`)
and every hover-highlight component (`StatusIcons.qml`,
`Workspaces.qml`, `DockWorkspaces.qml`, `MinimalIndicators.qml`,
`MinimalTray.qml`, `DockBar.qml`) all call through — picks whichever
candidate's **centre** is closest to the pointer position, with no
contains-test at all. That design is correct for same-sized
neighbours (individual icons in one pill, workspace cells), which is
the only case it had been used/verified against before. It silently
breaks when `Bar.qml`'s own **top-level entries** are hit-tested this
same way, because those vary wildly in size: the `agent` entry is
~40px tall; the `statusIcons` entry (all three status-icon pills
combined) is 300px+. For any position in roughly the first third of
`statusIcons`' own bounds — geometrically inside it, nowhere near
`agent` — `agent`'s centre (close to `agent`'s own small span) was
STILL closer than `statusIcons`' own centre (far from `statusIcons`'
own top edge, since it's such a tall entry), so `childAlong()` kept
resolving to `agent` well past `agent`'s real boundary. `agent` has no
hover popout, so nothing showed — exactly matching "network and
bluetooth don't pop out." The captured sweep data showed this
precisely: y=984–1024 all resolved to `agent` (`agent`'s real bounds:
y=985, height=40.8, i.e. it should have ended at ~1026) while
`statusIcons` genuinely starts at y=1030 — so `agent` was incorrectly
"winning" hit-tests for ~4px past its own real end purely due to
raw floating-point tie margins, which is fine — but the deeper problem
continued for another ~4-8px into `statusIcons`' own space before its
centre finally won, which for THIS bar's specific icon-count/pill-size
mix happened to land almost exactly at the boundary between
network/bluetooth (top of the Connectivity pill) and vpn/hostinfo
(rest of the same pill) — explaining "doesn't trigger until VPN"
precisely, not approximately.

**Fix:** `BarHit.nearestAlong` now checks every candidate's own bounds
first (`pos >= start && pos < start + size`) and returns immediately
on a real contains-hit, only falling back to nearest-centre when `pos`
isn't inside any candidate at all — the genuine "gap between two
adjacent icons" case this function was originally built for (still
needed, since `childAt()`-style exact testing returns nothing in a
gap). Fixed in the ONE shared singleton, so every call site listed
above is fixed at once — nothing else needed touching. **Verified with
a second instrumented `ydotool` sweep across the exact same y-range
after the fix**, showing a clean, correct progression:
y=1034→`network`, y=1064→`bluetooth`, y=1094→`vpn`, y=1114→`hostinfo`,
with `agent` correctly bounded to y≤1024. **The user independently
confirmed live** ("Both showed up that time") before this was written
up — this is the first fix in the whole 4/4b/4c/4d/4e/4f sequence
confirmed by an actual observed test, not code review alone.

**Debug instrumentation was temporary and has been fully removed** —
confirmed via `diff` that the repo and deployed `Bar.qml`/`BarHit.qml`
are byte-identical, and `journalctl` shows no `DEBUGPOPOUT` output
after the final reload.

**New standing capability for this environment:** `ydotool`/`ydotoold`
are now installed and known-working (with the 2x coordinate-scale
calibration noted above) — future hover/pointer-dependent bugs in this
project no longer need to be debugged blind from code and static
screenshots. `ydotoold` needs to be started per-session
(`sudo ydotoold --socket-own=<uid>:<gid>`, not currently a persistent
systemd unit) and `YDOTOOL_SOCKET=/tmp/.ydotool_socket` needs to be
set in whichever shell issues `ydotool` commands.

---

## Fixed this session (2026-08-29)

### 5. Aphotic Assistant: install silently failed to pull a model
User asked for the Assistant's status (see the earlier turn's research,
not re-duplicated here) and found it half-configured on this machine:
`~/.config/aphotic/assistant-system-prompt.md` was correctly rendered
with real install values, but `~/.config/aphotic/ai-config.json` didn't
exist and no model was pulled, so `AiProviders.qml` never added
"Aphotic Assistant" to the provider list despite the install otherwise
reporting done.

**Root cause, confirmed from real evidence, not inferred:**
`lib/install/assistant.sh`'s `resolve_assistant_model_via_llmfit()`
took `llmfit recommend`'s output, picked a median-by-size candidate, and
**guessed** an Ollama tag from the model's raw name via regex —
regardless of whether that model was ever actually published to
Ollama's registry. On this RTX 4090 (24GB VRAM), every single one of
llmfit's top 15 recommendations for the `general` use case had
`"ollama_name": null` — they're community fine-tunes in vLLM/AWQ/GPTQ
quantized formats (several with "uncensored"/"abliterated"/etc. in the
name), not real Ollama library entries. The guess heuristic turned the
selected candidate (`louismuk/gemma-4-26B-A4B-heretic-AWQ`) into
`louismuk/gemma:26.6b` — a plausible-looking but nonexistent tag.
Reproduced the exact derivation with a standalone script against the
real `llmfit recommend --json` output, not assumed. Cross-checked
against the live `ollama.service` journal from the actual install
window (21:38–22:25 on 2026-08-28): two `POST /api/pull` calls, each
returning in ~200ms — far too fast for a real download, exactly
matching an immediate "tag not found" rejection.

Checked `llmfit recommend --runtime llamacpp` (Ollama's own backend) as
a possible better filter -- still every candidate had `ollama_name:
null`; one (`OBLITERATUS/Gemma-4-12B-OBLITERATED`) had a real HF GGUF
repo (`mradermacher/Gemma-4-12B-OBLITERATED-GGUF`) that Ollama's
`hf.co/`-prefixed pull could theoretically reach, but picking an
arbitrary quantization file from an untrusted, oddly-named community
fine-tune as a stock installer default is a real quality/appropriateness
risk, not just a technical one — not pursued.

**Fix (matches the user's own stated theory — the recommended model
genuinely wasn't reachable via plain `ollama pull`):**
`resolve_assistant_model_via_llmfit()` now filters candidates to only
those where llmfit itself confirms a real Ollama tag (`ollama_name`
populated), and uses that tag directly — no more guessing. When nothing
qualifies (confirmed live: nothing did, on this hardware, today), it
correctly returns failure, and the caller (`setup_assistant()`) falls
through to the already-designed-for-this-exact-case
`ASSISTANT_FALLBACK_MODEL` (`llama3.1:8b`) instead of a broken guess.
Also fixed the identical bug in `services/LlmFit.qml`'s
`guessOllamaTag()` — the same heuristic backs Settings → AI's Hardware
Advisor one-click-pull button (`AiPane.qml`), which would have offered
the same class of broken pull; now returns `model.ollama_name` directly
or `""`, and the button's own `visible: recRow.tag.length > 0` already
correctly hides itself when there's nothing real to offer.

**Setup completed for real, not just fixed in the abstract:** ran the
corrected `setup_assistant()` flow by hand (skipping only the
already-redundant `sudo systemctl enable --now ollama.service` step,
since that service was already active+enabled) — `llama3.1:8b` pulled
successfully (4.9GB, verified via `ollama list`), `ai-config.json`
written with `assistantEnabled: true`, shell reloaded, confirmed live
that the `AiConfig.qml` FileView no longer warns "File does not exist"
for `ai-config.json`. The Assistant is genuinely active on this machine
now, not just theoretically fixed.

**Verified:** live, end-to-end, not code-review-only — real model pull,
real config file, real reload, real absence of the prior warning.

---

### 6. Notification icons not rendering for some notifications — root cause found and fixed
**Symptom reported:** "the icons not properly rendering for certain
notifications."

**Investigated at the Quickshell source level, not guessed.** Fetched
`quickshell-mirror/quickshell`'s actual `iconprovider.cpp`/
`iconimageprovider.cpp` via `gh api`. Confirmed: `Quickshell.iconPath
(icon, fallback)` — the two-argument overload both
`modules/notifications/Notification.qml` and
`modules/notificationcenter/NotificationHistoryItem.qml` call — only
ever resolves `icon` via `QIcon::fromTheme()`, i.e. as an icon-THEME
NAME. It never touches the separate raw-file-path resolution branch
(`QPixmap(path)`) the underlying C++ actually has, because that branch
is only reachable through a `path=` parameter neither QML call site
(nor the two-arg QML overload itself) ever sets. The freedesktop
notification spec explicitly allows a sending app's `app_icon` to be
EITHER a themed icon name OR a `file://` URI/absolute path — common
among Electron apps and some game launchers. When a sender uses the
path/URI form, `QIcon::fromTheme()` silently returns null (it's not a
theme name), and the notification falls through to the "image-missing"
generic glyph — the actual mechanism behind "certain notifications"
specifically, not all of them (apps that use a real theme icon name
were always fine).

Also found, while in `NotifData.qml`: a real `Notification.image` field
(Quickshell's own docs: "often something like a profile picture in
instant messaging applications") was already being read into
`NotifData.image`, but never actually rendered anywhere — a second,
independent gap (richer per-notification images, e.g. chat-app avatars,
silently ignored in favor of the generic app icon or glyph).

**Fix:**
- `Notification.qml` (live popup) and `NotificationHistoryItem.qml`
  (history panel): detect when `appIcon` looks like a path/URI
  (`startsWith("/")` or `"file://"`) and source it directly via
  `IconImage.source` (a plain `Image.source` alias, confirmed via
  Quickshell's own `IconImage.qml` source — natively handles absolute
  paths and `file://` URIs) instead of routing it through
  `Quickshell.iconPath()`'s theme-only resolver.
- `Notification.qml` only (history doesn't persist the `image` field —
  `NotificationHistory.qml` only stores `appIcon` — so this half of the
  fix doesn't reach there without a separate, larger change): prefers
  `modelData.image` over `appIcon` when present, matching the
  freedesktop spec's intent that the richer per-notification image
  should win when both exist.

**Verified live, not just code-reviewed:** sent a real test notification
(`notify-send -i /usr/share/pixmaps/kitty.png ...`) with a raw absolute
path as its icon — confirmed via screenshot that the real kitty icon
rendered correctly (previously would have shown the generic
"image-missing" glyph). Clean reload, no QML errors.

**Not fixed, deliberately out of scope for this pass (see the queued
item below for the larger version the user asked to have documented,
not built, right now):** this fix makes notifications correctly show
whatever icon the sending app actually provided — theme name, path, or
per-notification image. It does NOT change what happens when a sending
app provides NO icon at all (still the generic keyword-matched
`MaterialIcon` glyph from `Icons.getNotifIcon()`), and does NOT attempt
to cross-reference the sender against installed desktop entries the way
the launcher resolves app icons — that's real, separate, larger scope.

---

### 7. Quickshell segfault when switching themes from Settings → Appearance
**Symptom reported:** a real crash (`~/.cache/quickshell/crashes/ssa3r2rikt`,
`Signal: Segmentation fault (11)`), triggered by changing the theme.

**Root cause, read from the actual crash report, not guessed:**
`modules/wallpaperpicker/WallpaperFilmstrip.qml`'s `strip` `ListView` is
instantiated inside `WallpaperPickerWindow.qml`, whose `PanelWindow` only
toggles `visible: screenState.wallpaperPicker` — the QML item tree
underneath, including `strip`, stays alive and reactive even while the
picker window is closed. `strip.model: Themes.wallpapersInActiveTheme` is
a live binding to a `readonly property list<string>` on `Themes.qml` that
recomputes whenever the active theme changes. Clicking a theme card in
`AppearancePane.qml` calls `Themes.setTheme(...)`, which reassigns
`activeThemeInfo` and so `wallpapersInActiveTheme` — resetting the
(currently hidden) filmstrip's `ListView.model`. Qt's `QQuickItemView::
setModel()` resets `contentX` to 0 as part of that reset, which
synchronously re-entered this file's own `onContentXChanged` handler,
which wrote `strip.currentIndex`, which fired `onCurrentIndexChanged`,
which called `Themes.setWallpaperInActiveTheme(model[currentIndex])` —
all while `setModel()` was still mid-update. The crash's own stacktrace
matches this exactly: `QQuickMouseArea::mouseReleaseEvent` (the theme
card's click) → a property-write chain → `QQuickItemView::setModel` →
`setContentX` → re-entrant QML binding evaluation → a segfault inside
`QQmlDelegateModel::model()`, reading the view's model mid-swap.

**Fix:** both `onContentXChanged` and `onCurrentIndexChanged` in
`WallpaperFilmstrip.qml`'s `strip` now bail out immediately when
`!root.screenState.wallpaperPicker` — neither handler's logic (tracking
flick position, committing a wallpaper choice) is meaningful while the
picker isn't open, so there's no reason to let a model reset caused by
switching themes elsewhere re-enter them at all. Minimal, targeted fix;
did not change the window's lazy-instantiation pattern (`WallpaperFilmstrip`
staying persistently alive behind a hidden window is itself a real
question worth revisiting, but wasn't required to fix this crash).

**Verified:** clean reload after the fix
(`systemctl --user status aphotic-shell.service` active/running,
`journalctl` shows no new errors), config synced to
`~/.config/quickshell/aphotic`. **Not independently reproduced live**
(no theme-switch click was scripted this pass) — the fix is derived
directly from the crash report's own stacktrace and the two files' real
code, not from guessing at symptoms, but a real theme-switch click at
the desk is still worth doing once to confirm the exact crash is gone.

---

### 8. AI Chat tab: Ollama wasn't reachable out of the box, Claude/Codex gated on the wrong signal, no way to start Ollama from Settings
**Symptom reported:** "I can't get the aphotic assistant chat to work
and Ollama chat doesn't show up," despite Ollama and the Assistant model
both being installed and running; wanted a "Start/Serve Ollama" action
in Settings → AI instead of requiring `localhost:11434` to already be
configured by hand.

**Root cause 1 — `AiConfig.ollamaHost` defaulted to `""` forever.**
`services/ai/AiConfig.qml`'s config `FileView` never had a saved host on
a fresh install, and previously just left `ollamaHost` blank rather than
falling back to anything — deliberately, per an existing comment, to
avoid ever hardcoding one person's remote LAN address for everyone. But
that same caution accidentally also blocked the always-safe local case:
the `ai` layer installs and starts `ollama.service` unconditionally, and
Assistant setup (item 5 above) pulls a real model onto it, yet nothing
ever told this config file about the Ollama that's already running on
`127.0.0.1:11434` — so `ollamaHostConfigured` stayed `false` forever,
and both the Ollama provider and the Assistant (which also requires
`ollamaHostConfigured`) silently never became available. **Fixed:**
falls back to `Quickshell.env("OLLAMA_BASE_URL")` if set, else
`http://127.0.0.1:11434` (loopback only, never a remote address — a
different, always-safe class of default than the one the original
comment was guarding against). **This is now the out-of-the-box
default**, confirmed live: fresh `ai-config.json` shows
`"ollamaHost": "http://127.0.0.1:11434"` with no manual step needed.

**Root cause 2 — Claude was gated on an API key its own code path never
reads.** `AiProviders.qml`'s `claudeAvailable` was
`AiKeys.hasAnthropicKey`, but `sendMessage()`'s Claude branch is a CLI
subprocess (`claude -p <text>`) that authenticates via the `claude` CLI's
own login session, never via a stored key — so Claude could never
actually become "available" through Settings no matter what was
configured, and the missing-key warning text was actively wrong for this
provider. **Fixed:** `claudeAvailable` now reflects real CLI login state,
checked via a `claude auth status` subprocess
(`claudeCliPresent`/`claudeLoggedIn`, refreshed on load). Verified live —
the user ran `claude auth status` directly and confirmed
`{"loggedIn": true, "authMethod": "claude.ai", ...}`.
`IntelligenceInput.qml`'s warning text now has a Claude-specific branch
("CLI isn't installed" / "not logged in, run `claude login`") instead of
the generic "set an API key" message.

**Fix 3 — added a "Start Ollama" control.** `AiPane.qml` gained a new
Status row above the existing Model row: an icon that toggles between
`check_circle` (reachable) and `power_settings_new` (not), a description
showing Starting…/Running at `<host>`/Not reachable at `<host>`, and a
pill button that calls a new `AiProviders.startOllama()` — runs
`Quickshell.execDetached(["ollama", "serve"])` then polls
`refreshOllamaModels()` on a short retry timer (700ms × up to 8 attempts)
until reachable or attempts exhausted, rather than requiring a manual
terminal command or a shell restart.

**Codex, added on request as a parallel to the Claude fix — explicitly
UNVERIFIED, `codex` isn't installed on this machine.** Confirmed absent
(`command -v codex`, `pacman -Si codex`, `yay -Si codex` all fail), but
Aphotic's own `agent_usage.py` already treats `codex` as a first-class
recognized provider (`PROVIDER_IDS`, `~/.codex/sessions/*.jsonl`), and
the architectural shape matches Claude exactly (a CLI with its own OAuth
session), distinct from "ChatGPT," a raw HTTP API that would genuinely
need a stored key. Added, all flagged unverified in-code: a `codex`
entry in `_baseProviders`; `codexCliPresent`/`codexLoggedIn` +
`refreshCodexAuth()` (`codex login status`, defensive JSON-or-regex
parsing); a `sendMessage()` dispatch branch (`codex exec <text>`, a
good-faith guess at the CLI's non-interactive shape modeled on
`claude -p`) and a matching `codexProc` `Process` (stdout/stderr
`StdioCollector`s mirroring `claudeProc`'s exact pattern). Verified only
that this **doesn't break anything** when the binary is absent — reload
is clean, and the only related log line is the expected
`WARN: Process failed to start ... "codex" "login" "status"`, which
`codexCliPresent` staying `false` already handles gracefully (Codex
correctly shows as unavailable). **Not verified against a real `codex`
binary at all** — the `login status` command shape and `exec <text>`
invocation are both guesses; whoever next has the CLI installed should
treat this as a first real test, not an established working feature.

**Explicitly out of scope this pass, per the user's own framing ("BUT I
suspect we remove the API key and setup oAuth support... If the oauth
lift for the other providers is low effort... do it now" — assessed as
NOT low effort, documented instead):**
- **Real OAuth login for Gemini and ChatGPT specifically.** Unlike
  Claude/Codex, Aphotic's Gemini/ChatGPT providers are raw HTTP `curl`
  calls against the public REST APIs, which genuinely require a bearer
  token — a CLI tool's own OAuth session (if one even exists for these)
  is not architecturally interchangeable with that. Real OAuth here
  means registering an OAuth app with each provider, standing up a
  browser-based authorization-code flow, and building real token
  storage/refresh — a genuinely large, separate feature, not a
  low-effort extension of the Claude/Codex CLI-session pattern.
- **A Settings UI for configuring codex/opencode/anthropic API keys as
  named variables**, as the user separately described wanting kept/added
  alongside the OAuth work — `AiKeys.qml`'s chmod-600 file/pattern
  already exists for this; what's missing is a per-provider Settings row
  exposing it (the AI pane currently doesn't surface an add/edit key UI
  at all, based on the pass this session). Real, scoped, small-to-medium
  work — not attempted this pass, recorded so the ask isn't lost.

**Verified:** clean reload (`systemctl --user status
aphotic-shell.service` active/running, `journalctl` shows no QML errors
tied to any of these files — only the expected "codex binary not found"
process warning), config fully synced to `~/.config/quickshell/aphotic`
(`AiConfig.qml`, `AiProviders.qml`, `AiPane.qml`,
`IntelligenceInput.qml`). **Not independently click-verified** — no
pointer-simulation session was run this pass (`ydotoold` from item 4f
was not restarted); the Ollama host default and Claude auth-state fix
were confirmed via direct file/CLI inspection instead (`ai-config.json`
contents, the user's own `claude auth status` output), which is a real
but different kind of verification than an actual UI click-through.
Worth a real click through Settings → AI (Ollama Start button, provider
pills lighting up correctly) next time the shell is used interactively.

---

## Fixed/added this session (2026-08-29, continued)

### 9. Launcher grid mode: no left/right nav, hard-capped results (queued items B.1/B.2, now fixed)
`Launcher.qml`'s search `TextInput` had no `Keys.onLeftPressed`/`onRightPressed`
at all -- added, calling `grid.moveCurrentIndexLeft()`/`Right()` when
`useGrid`, falling through (`event.accepted = false`) otherwise so cursor
movement in list/prefix modes is untouched. Separately, both the apps-mode
`ListView` model (line ~416) and the `GridView` model were pre-truncating
to `Tokens.sizes.launcher.maxShown`/`gridMaxShown` via `.slice(...)` --
correcting the ledger's own prior note that "list mode doesn't have this
ceiling" (it did, for the apps case specifically). Both now pass the
unsliced `root.appResults` into their model; each view's own height stays
capped at the same visual budget as before (`shown`/`shownRows`), so
`ListView`/`GridView`'s native Flickable scrolling reaches entries past
the visible window instead of silently dropping them -- same pattern
clipboard/project modes already used safely elsewhere in this file.
**Verified:** clean reload, config synced. Not independently click/scroll
-tested this pass (no working pointer-sim session, see below).

### 10. Wallpaper/theme picker did not recolor the shell — real root cause found and fixed, live-verified
**Symptom reported:** picking a wallpaper/theme changed the wallpaper but
not the bar/UI colors; user described it as "static" and said the picker
"doesn't use any kind of back end function to change the colors."

**Investigated with real evidence, not assumed:** confirmed `Themes.
setTheme()` and `Wallpapers.setWallpaper()` were genuinely firing (matching
`sudo papirus-folders -C <color> ...` calls in the journal for many
different themes clicked across two earlier testing sessions), and that
`wallust` was genuinely succeeding and rewriting `~/.local/state/aphotic/
palette.json` with fresh, correct, per-theme values (confirmed via `aphotic
theme set <name>` + reading the file back) -- so the apply pipeline itself
was not broken. Then confirmed, by sampling actual bar pixel colors from a
screenshot across three different applied themes, that the **rendered
bar never changed** — every theme produced the exact literal hardcoded
fallback colors from `Colours.qml`'s `?? "#1F1F1F"` / `?? "#000000"`
ternaries, meaning `Colours.qml`'s `_raw` was never picking up the real
palette. Instrumented the deployed `Colours.qml`'s palette `FileView`
(`onLoaded`/`onLoadFailed`) with temporary `console.log`s (removed before
finishing) and proved live: the FileView loads correctly once at shell
startup, then **never fires again** no matter how many times `wallust`
rewrites the file afterward (`watchChanges: true` alone does not reliably
re-trigger on this kind of external rewrite) — the exact same class of bug
already diagnosed and fixed for `theme.json` in `Themes.qml` (see that
file's own comment), just never applied to `Colours.qml`'s palette watch.

**Fix:** `Colours.qml` gained the same 1s polling `Timer` calling `paletteFile.
reload()` that `Themes.qml` already uses for its own state file, with a
comment cross-referencing both the live instrumentation finding and the
`Themes.qml` precedent. **Verified end-to-end, live, by the user**
("That did it") — confirmed via pixel-sampled screenshots before/after
across `tokyonight`/`hackthebox`/`gruvbox`, and independently by the user's
own eyes on the real desktop.

### 11. Settings panel: fixed size grown for 14 categories, About pane re-centered
Fixed `SettingsPanel.qml` size was `980x560`, unchanged since ~5-6
categories; 14 exist today and several panes (AI, Network, Personalization)
had grown dense enough that the old size read as cramped (user's own
words: "dimensions are stuffed"). Bumped to `1180x720` -- still comfortably
fits the smallest documented target resolution (1920x1080). **Verified
live** via screenshot + user confirmation ("MUCH better size").

Bumping the panel's height made `AboutPane.qml` (logo + four short lines,
the sparsest pane in the panel) noticeably more top-heavy. Applied the
exact same `Layout.fillHeight: true` spacer-Item-above-and-below pattern
`LauncherPane.qml` already used for the identical problem (see "Fixed this
session (2026-08-28)" #2). **Verified live** via a temporary
`currentCategory: "about"` default-value flip (reverted after, matching
this repo's own established debug-verification convention) + screenshot.
Other panes (OSD, Clock, Displays, etc.) have enough real content to not
show the same dead-space problem and were left untouched — worth a real
look if any specific one is later reported as still feeling off.

Also removed the "Wallpaper art credits" heading + "All shipped theme
wallpapers are original, hand-authored art..." line from `AboutPane.qml`
on direct request -- no replacement text added, pane re-verified still
reads fine as just logo/name/version/repo-link.

### 12. New: SUPER+K keybinds cheatsheet — categorized, scrollable overlay
User asked for a dedicated SUPER+K surface showing every keybind,
categorized, scrollable, matching the existing UI. Data source
(`HyprKeybinds.qml`, reads `hyprctl binds -j` live) already existed for
the launcher's "!" search mode but had no categorization. Added:
- `HyprKeybinds.qml`: a `_categoryFor(description)` heuristic (keyword
  match against the same `description` text already shown elsewhere --
  Hyprland's bind schema has no room for a real custom category field
  that would survive the round trip through `hyprctl binds -j`, and this
  file's own header comment already documents why parsing `keybinds.lua`
  by hand instead of reading live state was rejected) sorting into six
  buckets (Aphotic Shell / Windows / Workspaces / Apps & System / Capture
  / Media & Hardware), and a `categorizedEntries` computed property
  grouping `entries` into those buckets in order, empty buckets omitted.
  Rule order deliberately puts more specific patterns first (e.g. "to
  workspace" before the generic "window" match) so e.g. "Move window to
  workspace N" lands in Workspaces and "Pin window (all workspaces)"
  correctly lands in Windows despite both containing "window"/"workspace"
  substrings -- verified against the live rendered output, not just
  reasoned about.
- New `modules/keybinds/KeybindsCheatsheetWindow.qml` -- same PanelWindow
  / click-outside / Escape-to-close shape as `SettingsWindow.qml`, a
  centered `900x780` sheet with a header (icon, title, live bind count,
  close button) and a `Flickable` column of category sections (label +
  divider + 2-column grid of combo-chip + description rows, reusing the
  launcher's own `KeybindItem.qml` chip styling for visual consistency).
- `ScreenState.qml` gained `keybindsCheatsheet: bool`; `shell.qml` gained
  a `Variants` block for the new window and a `keybindscheatsheet` entry
  in the existing generic `_toggleTargets` map (no new dedicated
  `IpcHandler` needed -- follows the file's own documented preferred
  pattern for new toggle-shaped surfaces); `keybinds.lua` binds
  `SUPER+K` to `qs -c aphotic ipc call aphotic toggle keybindscheatsheet`.

**Verified live, not just code-reviewed:** toggled via IPC, screenshotted
-- confirmed 87 binds, correct categorization (spot-checked "Pin window
(all workspaces)" landed in Windows, not Workspaces), correct live
theming across two different applied themes (tokyonight, gruvbox --
depends on item 10's fix above), clean reload, no QML errors.

**Process hygiene note for whoever next runs ad-hoc IPC calls from a
shell during dev:** `qs -c aphotic ipc call <target> <fn>` is the WRONG
argument order and silently launches a second full shell instance instead
of sending an IPC call (`-c` binds to `qs` itself, starting a new config
instance, not to the `ipc` subcommand) -- this happened live this session
("There are now 2 running QML bars in the instance") and had to be killed
by hand. The correct form is `qs ipc -c aphotic call <target> <fn>`
(config selector after `ipc`, per `qs ipc --help`).

### 13. Settings → Plugins "Install" did nothing — real root cause found, fixed, live-verified end to end
**Symptom reported:** clicking Install produced no output, no error, no
download/queue indication — button just sat there.

**Root cause, confirmed by running the actual CLI command directly, not
guessed from code alone:** `cmd_plugin.sh`'s `_aphotic_plugin_install()`
never cloned anything — it only ever `cp -r`'d a plugin subdirectory out
of `$APHOTIC_PLUGINS_REPO` (default `~/aphotic-plugins`), which nothing in
this codebase ever created. On a machine that never manually `git clone`'d
that repo by hand (this one included — confirmed absent), the CLI
correctly failed fast with a real, clear stderr message and exit code 1.
But `PluginsPane.qml`'s `actionProc` (the `Process` the Install button
runs through) had **no stdout/stderr collector and no exit-code handling
at all** — that real error was captured by nothing and shown nowhere,
which is the entire visible bug: a real, correct CLI failure with zero UI
feedback path for it to travel through.

**Fix, two parts:**
- `cmd_plugin.sh`: new `_aphotic_plugin_sync_repo()` clones
  `$APHOTIC_PLUGINS_REPO` from a new `APHOTIC_PLUGINS_GIT_URL`
  (`globalcontrol.sh`, matches the org/repo `APHOTIC_PLUGINS_INDEX_URL`
  already points at) if missing, or `git pull --ff-only`s it if present
  (a pull failure warns and falls through to the existing checkout rather
  than blocking — same "warn and continue" convention this file already
  uses for hook failures). `_aphotic_plugin_install()` now calls this
  first, and ends with a literal `echo "PLUGIN INSTALLED: ${name}"` on
  success, per the user's own requested output contract. **Verified by
  running it for real, not just reading it:** `aphotic plugin install
  openrgb` on this machine (no prior local checkout) cloned
  `github.com/T-Crypt/aphotic-plugins`, copied the `openrgb` plugin,
  printed `PLUGIN INSTALLED: openrgb`, exited 0 — confirmed installed via
  `aphotic plugin list --json` and the real files on disk afterward.
- `PluginsPane.qml`: Install's click handler no longer runs through the
  silent `actionProc` at all — per explicit request, it now spawns the
  exact same `aphotic plugin install <name>` command (same CLI, no
  reimplemented logic) inside a real, visible `kitty --hold -T "Installing
  <display name>" aphotic plugin install <name>`. `--hold` keeps the
  window open after the command exits (success or failure) instead of it
  vanishing the instant install finishes, so the output — including the
  new clone/pull step — is actually readable. No windowrule floats kitty
  (checked `Configs/hypr/windows.lua`), so it tiles normally per the
  request. Since install now runs outside any tracked `Process`, the pane
  gained a 2s polling `Timer` calling `root.refresh()` (same "cheap and
  self-correcting" convention `Themes.qml`/`Colours.qml`'s own state-file
  polling already established this session) so "Install" flips to
  "Installed" once the terminal's install actually finishes, with no
  manual reopen needed.

**Verified live:** clean reload, no QML errors; a temporary
`currentCategory: "plugins"` default-value flip (reverted after, same
established debug convention as item 11's About-pane check) + screenshot
confirmed the already-CLI-installed `openrgb` plugin correctly shows
"Installed" in both the Installed section and the Browse-available list,
with its real `missing_binaries: ["openrgb"]` flag surfaced ("Missing
dependency: openrgb" — the `openrgb` CLI itself isn't installed on this
machine yet, separate from this plugin-system fix; the user has real
OpenRGB-compatible hardware to test against and will need to install that
package separately). **Not yet click-tested through the actual UI button**
(no working pointer-sim session this pass) — the underlying command is
proven correct standalone and the QML change is a thin, low-risk swap
(`Quickshell.execDetached` and polling `Timer` are both patterns already
used elsewhere in this codebase), but a real click on "Install" for
`direnv` or `workspace-session-log` (still uninstalled, safe to test
against) is worth doing at the desk to confirm the kitty terminal actually
pops up tiled and shows the expected output.

### 14. Plugins pane: category filter visibly off-center from the browse list next to it
**Symptom reported:** the category-pill box (All/Dev Tools/Security
Tools/...) looked offset relative to the "Browse available" plugin list
beside it.

**Root cause:** the category filter reuses `CategoryRail.qml` — the same
component driving the *main* Settings navigation rail, which always
renders its own search box ("Search settings…", wrong copy for this
context too) above the category list. That box (~48px) pushed every
plugin-category pill down by that much with nothing equivalent on the
neighboring browse-list column, so the two columns' content started at
different vertical offsets. Separately, the fixed `300`px height on both
columns was already too short for the real content — 7 categories at
~60px/row with no inter-row spacing need ~420px, so the category list was
also internally scrolling for no good reason at that size.

**Fix:** `CategoryRail.qml` gained a `showSearch: bool` property
(default `true`, so the main Settings rail's own search is untouched);
`PluginsPane.qml`'s instance sets `showSearch: false` and both fixed
column heights went `300 -> 400`, enough to show all 7 categories without
an inner scrollbar and to keep the two columns matched. **Verified live**
via screenshot before/after — pills and browse-list rows now start flush
at the same top edge.

---

## Documented, not built this pass (explicit user request: "I just want this documented")

### A. Notification icons: match launcher's real app-icon resolution + Aphotic-branded system notifications
Raised alongside item 6 above. Two related but genuinely separate
pieces of scope, both explicitly deferred to a roadmap item rather than
built now:

1. **Use the launcher's actual app-icon resolution as the notification
   icon source**, not just whatever raw `app_icon`/`image` hint a
   sending app happened to include. The launcher already has a real,
   working desktop-entry → icon resolution path (`DesktopEntries`-based,
   the same one `Icons.getAppCategoryIcon`-style helpers elsewhere in
   this codebase use). Notifications currently never cross-reference
   against that at all — they rely entirely on whatever the sending
   app's D-Bus notification payload happened to include (now correctly
   rendered when present, per item 6, but still absent for apps that
   send nothing). Real work required: matching a notification's sender
   (`appName`/`desktopEntry` field — `Notification.qml` already reads
   `modelData.appIcon`/`.appName`; `NotifData.qml` doesn't currently
   expose `notification.desktopEntry` at all, a small but real gap to
   close first) against an installed desktop entry, which is not
   guaranteed to be a clean 1:1 string match (app names in notification
   payloads don't always equal desktop-entry IDs) — genuine matching
   logic, not a lookup table.
2. **Aphotic-branded, per-theme notification treatment for
   system/Aphotic-originated notifications specifically** (e.g.
   `notify-send -a aphotic ...` call sites already used throughout this
   codebase's own scripts/hooks), using `assets/aphotic-mark-frame.svg`
   — already vendored in this repo and already wired into
   `components/AphoticMark.qml` (used somewhere in the bar per the
   user's own description; not yet audited for exactly where/how it
   themes per-palette as part of this documentation pass). Needs: (a) a
   real way to classify "this notification is Aphotic-system-originated"
   vs. a normal third-party app notification — the existing
   `-a aphotic` app-name convention is a plausible, already-in-use
   signal, but hasn't been confirmed as the actual mechanism to key off
   of; (b) a distinct visual template (not just swapping the icon) that
   reads as "this is the shell talking to you," themed by the active
   palette the same way `AphoticMark.qml` already handles elsewhere in
   the bar — needs auditing that component's actual theming mechanism
   before this can be scoped precisely, not assumed to be a drop-in
   reuse.

**Assessment: genuinely larger-lift, correctly not attempted in this
pass.** Item 1 needs real sender→desktop-entry matching logic with a
fallback story for non-matches; item 2 needs a real system-vs-third-party
classification mechanism plus a new visual template, not just an icon
swap. Both are real, scoped feature work — added here so the shape of
the idea and the concrete blockers are on record, not lost.

### B. Launcher grid mode: no left/right navigation, hard-capped visible results, general polish requested
Raised by the user, explicitly to document only, not fix now. Verified
each specific claim against the code before writing it down here (not
assumed from the report alone):

1. **Confirmed: grid mode genuinely has no left/right keyboard
   navigation.** `modules/launcher/Launcher.qml:306-307` wires
   `Keys.onDownPressed`/`Keys.onUpPressed` to
   `grid.moveCurrentIndexDown()`/`moveCurrentIndexUp()` when
   `useGrid` is active, but there is no `Keys.onLeftPressed`/
   `Keys.onRightPressed` handler anywhere in the file. `GridView`'s own
   `moveCurrentIndexLeft()`/`moveCurrentIndexRight()` methods exist and
   would work the same way the existing up/down calls do — this is a
   real, narrow, well-scoped gap (two missing key handlers calling two
   existing GridView methods), not a design problem. Low-lift when it's
   next picked up, just not attempted in this pass since the ask this
   time was explicitly documentation-only.
2. **Confirmed: grid mode hard-caps visible results, no pagination/
   scroll.** `Launcher.qml:563`: `values: root.useGrid ?
   root.appResults.slice(0, root.gridMaxShown) : []`, where
   `gridMaxShown = gridColumns * gridRows` (a fixed cell count, per
   earlier docs 4×3 = 12). Once more than 12 apps match the current
   query (or no query, meaning most installed-app libraries), the rest
   are simply never shown — no scroll, no "+N more," no pagination.
   List mode (`useGrid: false`) doesn't have this ceiling. This is the
   concrete mechanism behind "cannot view all apps installed like you
   can in ROFI" — Rofi's drun mode scrolls/paginates through the full
   result set; Aphotic's grid mode silently truncates instead.
3. **"Polish the UI feel of app launcher, center and fix margins on
   grid mode"** — raised but not independently investigated this pass;
   no specific broken-margin/off-center measurement taken yet. Needs a
   real look (likely a live screenshot comparison against list mode's
   spacing) before it's more than a general impression on record.
4. **"Add [new?] Font options for browser + repo (unify the FONT)"** —
   raised in shorthand, meaning genuinely unclear as written: could be
   about Settings → Appearance gaining a font picker, could be about a
   specific mismatch between the browser's rendered font and the rest
   of the shell/repo's own typography (`Tokens.font.*`), could be about
   something else entirely. Needs a clarifying follow-up with the user
   before this is actionable — recorded here verbatim rather than
   guessed at, so the ask isn't lost, but genuinely not yet scoped.

**Assessment:** items 1 and 2 are real, confirmed, narrow bugs/gaps —
either would be a reasonable low-lift pickup next time grid-mode
launcher work comes up. Items 3 and 4 need more investigation/
clarification before they're actionable; recorded as raised, not as
confirmed findings.

*(Launcher grid items A/B above already covered the "up/down only,"
"can't view all apps," "polish/margins," and "font unification" asks
re-raised in a later message the same day — not duplicated here, this
note just confirms they were captured, not missed.)*

### C. Agent bar popout: static positioning, X-button-only dismiss, inconsistent with the rest of the popout system
Raised the same day, explicitly documentation-only ("LEDGER ONLY — NOT
NOW"). Lightly verified before writing down (not assumed from the
report alone), given how much of this session was spent on the regular
popout system's hover/dismiss behavior — worth being precise about
exactly how the agent popout differs, not just noting "it's different."

**Confirmed: the agent popout's dismiss mechanism is a manual close
button, not hover-driven.** `popouts/AgentPopout.qml:14-35` — a header
row with an "Agents" title and a `MaterialIcon { text: "close" }` plus
its own `MouseArea`, `onClicked: root.screenState.agentPanel = false`.
This is the literal "requires X in top right" the report described.
Contrast with every other bar popout (`network`, `bluetooth`, `vpn`,
`resources`, etc., all routed through `popouts/Wrapper.qml`'s main
`flyout`), which — after this session's whole 4/4b/4c/4d/4e/4f
investigation — now dismiss via hover-exit through
`BarWrapper.qml`'s `hoverHandler` + `hoveringFlyout` guard, with no
manual close button anywhere in that path.

**Positioning is genuinely live-tracked already, contrary to a literal
reading of "static location"** — `popouts/Wrapper.qml`'s `agentCenter`
is kept current via a `Qt.binding()` set in `Bar.qml`'s
`Component.onCompleted`, continuously re-evaluating the agent bar
entry's own `centerAlong` position, and `agentFlyout`'s `x`/`y` derive
from `agentCenter` the same structural way the main `flyout` derives
from `currentCenter`. So the agent popout does follow the agent icon
if the icon itself moves (e.g. reordering bar entries, orientation
swap) — the "static" complaint is much more likely about *interaction
model* (open-by-click + close-by-X-button, staying open indefinitely
otherwise, no hover-away dismiss) than about geometry not updating.
Worth confirming this distinction with the user before any fix work
starts, rather than assuming "static" meant "position never updates."

**Not investigated this pass (explicitly deferred):** whether
`agentFlyout` shares `flyout`'s zero-gap-to-bar fix (4c) and the
region/mask fixes from the 4/4b/4c/4d/4e/4f sequence, or whether it has
its own independent (and possibly still-buggy) geometry path that
happened not to get touched during that whole investigation since the
user's reports throughout were about hover popouts, not the
click-opened agent panel specifically.

**Real work to "unify this with the new popout structure," roughly
scoped but not started:** decide whether the agent popout should
switch to the same hover-exit dismiss model the rest of the system now
has (would mean giving up click-to-open-and-stay-open, a real behavior
change someone opening the agent panel to read multiple session rows
might not want) or keep click-to-open/explicit-close by design (agent
sessions are the kind of thing you might want pinned open while working,
unlike a quick network-status glance) but make that an intentional,
documented exception rather than something that just reads as
inconsistent. This is a real product decision, not just a code fix —
flagging it as one rather than assuming "make it match the others" is
obviously correct.

### D. GTK per-theme/per-app config — audit whether it's already wired up; general QoL + full QML audit requested
Raised the same day, explicitly documentation-only. Not investigated
this pass at all (the user's own framing: "ADD or review... LEDGER
ONLY — NOT NOW") — recorded as a real open question, not a confirmed
gap, since the answer could go either way and hasn't been checked:

- Does Aphotic's theming pipeline (wallust-driven palette generation,
  per-theme `~/.config/awww/<name>/` directories) already apply to GTK
  apps on a per-theme basis, and is there any per-app override
  mechanism, or does GTK theming stop at whatever `gtk3`/`adw-gtk-theme`
  (both already in `profiles/base/full.toml`'s package list) provide
  out of the box with no Aphotic-specific per-theme color derivation?
  A real answer needs checking `wallust.toml`'s template list for a
  GTK CSS target (matching the existing `quickshell`-template precedent
  documented elsewhere in this repo's history) and whether any
  `cmd_theme.sh`/`Themes.qml` call site touches `~/.config/gtk-3.0/` or
  `~/.config/gtk-4.0/` at all.
- **"Add QoL review and full QML audit"** — as broad as it reads: no
  specific target given yet (which module(s), what "QoL" means in this
  context — missing keybinds? undocumented settings? something else?).
  Recorded verbatim so the ask isn't lost, but this needs real scoping
  (probably a dedicated session, not a single pass) before it's
  actionable — closer to "the user wants a broad health-check sweep at
  some point" than a specific fixable item right now.

---

## Process change (2026-08-29): repo went from solo dev to community project mid-session

Repo hit real traction the same day this session ran (9 stars in 6 hours,
200+ upvotes on the user's own Reddit post). User's explicit direction:
get `main` as stable as possible, stop pushing directly to `main`, PR
everything from here forward. Acted on immediately, not just noted:

- This session's in-flight work (items 9-14 above) was committed as one
  checkpoint directly to `main` (`f5b0eae`) — the one explicitly-approved
  exception before the new rule took effect, not a precedent for future
  sessions.
- **Real GitHub branch protection enabled on `main`** (not just a written
  convention): PR required for everyone including the repo owner
  (`enforce_admins: true`), 0 required external approvals (still sole
  maintainer, so self-merge stays open), no force-push, no branch
  deletion, all review threads must resolve. Required status checks
  (`test`, `shellcheck`, `bash-syntax`, `CodeQL`, `strict: true` so the
  branch must be current with `main`) were added in a second pass once
  `Tests` was confirmed green — see the next item for why it wasn't
  green initially.
- **Found and fixed a real, pre-existing CI failure while setting this
  up**: `tests/test_profiles_real.py::test_exploit_layer_adds_packages`
  had been failing on `main` for at least the two most recent pushes
  (confirmed via `gh run list`) — it asserted against `profiles/layers/
  exploit.toml` directly, which deliberately carries no `[packages]`
  block since the `expand_layer_bundles()` refactor (see that file's own
  header comment); the packages it expects only exist in the three real
  sublayers (`exploit-recon`/`exploit-web`/`exploit-network`) that
  function expands `exploit.toml`'s `bundles` list into at actual
  install time. Also asserted a stale `dirbuster`, replaced by
  `gobuster` in `exploit-web.toml` at some point with the test never
  updated (confirmed `dirbuster` appears nowhere else in the repo).
  Fixed to pass the same three sublayers, checked `gobuster`. Landed via
  [PR #15](https://github.com/T-Crypt/aphotic-hypr/pull/15) — the first
  PR through the new workflow, all checks green, merged. **This is the
  template for every fix from here on**: branch, commit, push, PR, wait
  for green CI, merge (self-merge fine solo, real reviewer once there's
  one) — never a direct push to `main` again, enforced server-side now,
  not just by discipline.
- **VM validation workflow, agreed but not yet exercised this session**:
  install.sh-related changes specifically get validated on the dev VM
  (`10.0.0.26`) before merge; other changes test on whichever machine
  makes sense given what the user's actively doing at the time (their
  own words: "I might be working on this so we need to use the Dev VM").
  No install.sh-touching change has come up yet this session to actually
  run this against.
- Repo's canonical GitHub location changed case (`T-Crypt/Aphotic-Hypr`
  -> `T-Crypt/aphotic-hypr`, old one now redirects) — local `origin`
  remote updated to the canonical URL to stop the push-time redirect
  warning.
- Deleted `fix/install-blackarch-checksum` (remote branch, already
  merged via PR #13) on request — confirmed merged before deleting, not
  just assumed from the name.

---

## Fixed this session (2026-08-29, `fix/active-QoL` branch)

Everything below is on a real branch per the new workflow, not `main`
directly.

### 15. Dead code removed: two unused ScreenState properties, three unused components
Re-verified each against the tree before removing (not just trusting the
prior session's note) — `grep`-confirmed zero real consumers, not
assumed:
- `components/ScreenState.qml`'s `utilities`/`sidebar` — the only hits
  for a naive `.utilities`/`.sidebar` grep were `GlobalConfig.utilities`
  (an unrelated property on a different singleton), so these two really
  were dead. Removed.
- `components/AnchorAnim.qml`, `components/AnimLoader.qml`,
  `components/effects/Elevation.qml` — the only apparent hits
  (`AnchorAnimation` in `BackgroundWindow.qml`, a real Qt Quick built-in
  type that just substring-matches "AnchorAnim"; `Elevation.qml`
  mentioned only in a code comment in `BioluminescentGlow.qml`, never
  instantiated) were false positives once checked. Deleted all three
  files plus their now-dangling `qmldir` export lines
  (`components/qmldir`, `components/effects/qmldir`).

**Verified:** clean reload, no QML errors tied to any of these files
(one transient `Failed to open file ... Elevation.qml` warning came from
the *old*, already-shutting-down process rescanning during the reload
window itself, not the new one — confirmed by checking which PID logged
it).

### 16. Real bug found while cleaning up: the constant `QColor::setAlphaF: invalid value nan` spam, present the entire session, had a real fix
This warning had been firing continuously (~4/sec) in every journal check
all session, dismissed each time as pre-existing noise alongside the
genuinely-unfixable papirus/upower/codex warnings. Worth a real look once
the session's focus shifted to stability — it wasn't unfixable, just
never chased.

**Root cause:** `components/StateLayer.qml`'s ripple-effect gradient
(the fill animation every clickable surface in this shell uses) computes
two `GradientStop` positions/colors by dividing by `root.circleRadius`
(line ~137) and `root.endRadius` (line ~142). Both are `0` before a
`StateLayer` is ever pressed (`circleRadius` has no initializer;
`endRadius` is computed from the layer's own `width`/`height`, which are
genuinely `0` for any `StateLayer` sitting on a collapsed-to-zero-size
parent — e.g. `Media.qml`'s icon while `Players.active` is null, per its
own `implicitWidth: active ? ... : 0`). `0/0` is `NaN` in JS, `Math.max`/
`Math.min` do not sanitize `NaN` (it propagates through both), and the
result feeds straight into `Qt.alpha()`, which rejects it -- the exact
warning, on a binding that's live on essentially every clickable element
in the entire shell, which is why it never stopped.

**Fix:** floored both denominators with a `Math.max(x, 0.001)` epsilon.
The ripple is already invisible at `circleRadius` 0 (unpressed, opacity
0) regardless of what these two stops evaluate to, so this changes zero
visible behavior for any real (non-degenerate) press animation and only
eliminates the `0/0` case.

**Verified live, not just reasoned about:** `journalctl` showed the
warning firing every reload, all session, right up through the previous
fix's own verification checks (0 occurrences filtered out as known
noise). After this fix: **zero** occurrences over a clean 15-second
window post-reload, single running instance confirmed. This is the kind
of thing "get main stable" surfaces once you stop filtering it out as
expected noise.

### 17. Plugins: dependency binaries are now actually installed, not just labeled "missing"
User's ask: the Plugins pane already detects and shows "Missing
dependency: X" for a plugin's declared `[requires] binaries`, but never
did anything about it. Wanted a real install path, in the same kitty
terminal `aphotic plugin install` already opens (item 13 above), not a
second window.

**Implementation, reusing an existing precedent rather than inventing a
new one:** `PkgSearch.qml` (Settings -> package search, SUPER+Y) already
has a working "install a package in a real terminal" flow --
`Quickshell.execDetached(["kitty", ..., "${helper} -S \"$1\"", ...])`,
deliberately with no `--noconfirm` so yay/paru's own interactive prompts
(provider choice, PKGBUILD review, sudo password) show up exactly as
they would from a manual install, since AUR packages run arbitrary build
scripts. Ported the same `yay -S`/`paru -S`, no-`--noconfirm` contract
directly into `cmd_plugin.sh` as a new `_aphotic_plugin_install_deps()`,
called from `_aphotic_plugin_install()` right after the plugin's files
are copied/linked, in the same shell process -- so the terminal shows
one continuous clone -> copy -> install-deps -> done flow, not two
separate windows.

Reads each missing binary from the plugin's own `plugin.toml`
(`requires.binaries`, already parsed for the "missing" label) and
installs a package of the **same name** by default -- correct for the
common case (the `openrgb` binary really does come from a package
literally named `openrgb`). Also supports an optional, explicit
`[requires] packages = [...]` in plugin.toml as an override for the
less-common case where a binary's package name differs from the binary
itself; falls back to the binary-name default when that key is absent,
so no existing plugin manifest needs to change for this to work.

**Verified live, not just read through:** removed the already-installed
`openrgb` plugin, reinstalled via `aphotic plugin install openrgb` --
confirmed it correctly detected the missing `openrgb` binary, correctly
resolved and attempted `yay -S openrgb` (found the real AUR/repo package,
`openrgb-1.0rc3-3`), and only failed to actually complete the install
because the test itself ran through a non-interactive shell with no real
TTY for sudo's password prompt (`sudo: a terminal is required...`) --
exactly the kind of prompt a real kitty window provides normally. Failed
gracefully (warned, did not abort the plugin install itself, still
printed `PLUGIN INSTALLED: openrgb`) rather than crashing. The user has
real OpenRGB-compatible hardware and intends to complete this install for
real through the actual UI button, where the sudo prompt will work.

### 18. SDDM login background sync was never actually working automatically — two independent real bugs, both fixed
User's ask, paraphrased: stop requiring a human to manually run `aphotic
sddm sync`; make the login-screen background track the active desktop
wallpaper on its own.

**Investigated before building anything new, and found the automatic
trigger already existed** -- `Wallpapers.qml`'s `setWallpaper()` (fires
on every theme/wallpaper change) already calls `aphotic sddm sync` as a
best-effort background call, and has since before this session. So the
real question was why that already-automatic call was never actually
taking effect.

**Bug 1, the real blocker:** `cmd_sddm.sh`'s sync/greeting functions
unconditionally wrapped every write in `sudo cp`/`sudo sed`, gated on
`sudo -n true` (passwordless sudo). But `install.sh`'s own
`install_sddm()` already `chown -R "$USER:$USER"`s the entire SDDM theme
directory right after extracting it, specifically so ordinary desktop
use doesn't need root there at all -- confirmed live on this machine
(`ls -ld /usr/share/sddm/themes/sugar-candy` -> owned by the desktop
user, `rwxrwxrwx`). The `sudo` requirement was pure unnecessary
friction: it only ever "worked" when a sudo credential happened to
already be cached from some other interactive command, and silently
no-op'd on every genuinely-automatic call otherwise (matching the many
"needs passwordless sudo" warnings seen in this session's own earlier
journal checks). **Fixed:** both functions now try a direct, sudo-free
write first (`[[ -w ... ]]` check), falling back to the old sudo-gated
path only for a theme directory some other setup left root-owned.
**Verified live:** `aphotic sddm sync` now succeeds with zero sudo
prompt, confirmed the new background file landed user-owned and
`theme.conf`'s `Background=` line updated correctly.

**Bug 2, found while adding the periodic timer requested alongside the
above (defense-in-depth for wallpaper changes that bypass this repo's
own code paths entirely, e.g. a raw `awww img` call):** new
`aphotic-sddm-sync.service`/`.timer` (`Configs/systemd/user/`, matching
the existing `aphotic-agent-usage` unit pair's exact shape,
`OnUnitActiveSec=5min`) failed on its first real run --
`ExecStart=/usr/bin/env aphotic sddm sync` couldn't resolve `aphotic` at
all (`env: 'aphotic': No such file or directory`). **Checked whether the
already-existing `aphotic-agent-usage.service` had the identical bug
rather than assuming it was fine, since it uses the exact same
`/usr/bin/env aphotic ...` shape** -- it did: `journalctl --user -u
aphotic-agent-usage.service` showed it failing on **every single
15-minute run since this machine's install**, with the exact same error.
`systemd --user` services run with a minimal environment that doesn't
include `~/.local/bin` in `PATH` (that only happens in an interactive
shell via `.zshrc`/`.bashrc`), so `env aphotic` could never have worked
from either unit. This means the "Live Agent Activity Module" this
timer exists to feed has never actually been getting fresh data on this
machine -- a real, independent, previously-undiscovered bug, caught only
because building the new timer the same way surfaced it. **Fixed both**
`ExecStart=` lines to use systemd's `%h` (user home) specifier for an
absolute path (`%h/.local/bin/aphotic ...`) instead of relying on `PATH`
at all. **Verified live:** both services now report `code=exited,
status=0/SUCCESS` on manual trigger, confirmed via `systemctl --user
status` on each.

`install.sh` gained one new line enabling the sddm-sync timer (mirroring
the existing agent-usage enable line exactly); the new unit files
themselves need no separate install.sh wiring since that script already
symlinks every file under `Configs/systemd/user/` generically. **This
specific install.sh change (and the two systemd unit files) should get
real dev-VM validation before merging**, per the session's own new PR
workflow -- not yet done as of this entry, next up.

### 19. Agent token usage showed 0 all session — three independent real bugs, all fixed, confirmed against real live usage
User's ask: "it's not calculating token usage for the agent either." Real,
severe bug — the bar's Live Agent Activity Module has apparently never
shown correct usage on this (or possibly any) machine. Found three
separate, independently-confirmed root causes, not one:

1. **The updater timer never actually ran** — same `/usr/bin/env aphotic`
   PATH bug as item 18's `aphotic-sddm-sync.service` discovery, and this
   is the unit that bug was originally found on: `aphotic-agent-usage.
   service` had been failing on literally every 15-minute trigger since
   this machine's last install (`journalctl` showed the identical `env:
   'aphotic': No such file or directory` going back hours). Fixed in item
   18 (`ExecStart=%h/.local/bin/aphotic ...`) — the state file wasn't
   even being regenerated, let alone correctly.
2. **`agent_usage.py`'s `main()` picked exactly one transcript file,
   arbitrarily.** `sources["claude"] = next(iter(home.glob(".claude/
   projects/*/*.jsonl")), ...)` — whatever file `glob()` happened to
   enumerate first, not the current session, not the most recent, not an
   aggregate. Confirmed live: on this machine (38 real transcript files
   across many project directories), that picked a completely unrelated,
   long-stale project directory from what looks like a prior username on
   this box (`-home-trevin-...`), guaranteeing 0 tokens regardless of how
   much real usage was happening in the actual active session. **Fixed:**
   `build_usage_record`'s `sources` now accepts a `Path` (existing tests,
   unchanged) or a `list[Path]` (real usage), summing today's tokens
   across every matching file for that provider instead of picking one.
   New regression test (`test_multiple_transcripts_for_one_provider_are_
   summed_not_picked_one`) locks this in with two fixture files.
3. **The parser's assumed JSON shape didn't match a single real
   transcript line.** `_sum_transcript` read `entry.get("model")`/
   `entry.get("usage")` at the top level of each JSONL line — but a real
   Claude Code transcript nests both under `entry["message"]` (confirmed
   directly against this session's own live transcript file, not
   assumed). This function's *own* test fixtures used the flat shape it
   expected, which is exactly why this was never caught by the existing
   tests — they tested the code against the shape the code assumed,
   not the shape Claude Code actually writes. **Fixed:** checks top-level
   first (keeps every existing fixture/test working unchanged), falls
   back to `message.model`/`message.usage`. New regression test
   (`test_real_claude_transcript_shape_nests_model_and_usage_under_
   message`) uses a fixture shaped like a real transcript line.

**Verified end-to-end against real, live data, not just passing tests:**
after all three fixes, manually triggering the (now-working) systemd
service produced `"todayTokens": 2793960` for `claude-sonnet-5` —a real,
plausible number for this session's actual length, not a fixture. All 18
tests pass (`pytest tests/ -v`).

**Not yet investigated this pass — the second half of the same user
report:** the bio-glow / active-session icon near the agent bar
indicator not appearing while an agent is active. Separate rendering-
layer question from this data-pipeline fix; next up.

### 20. Agent bio-glow: one real config issue + one real rendering bug, both found and fixed live
Continuation of item 19's report ("not showing the active bio glow... or
the active sessions icon near the agent"). Two independent causes, not
one -- found by testing rather than reasoning from code alone.

**Cause 1 (config, not a bug in the glow logic itself): the wrong
provider was selected.** `AgentIndicator.qml` shows whichever provider
`Settings.agentSelectedProvider` currently points at (cycled via
middle-click) -- and on this machine it was persisted as `"ollama"`, not
the `"claude"` default, in `~/.local/state/aphotic/settings.json`
(checked the wrong file first, `~/.config/aphotic/shell.json` -- that
's not even `Settings.qml`'s real state path; confirmed the actual path
by reading `Settings.qml`'s own `statePath` property before re-checking).
With Ollama selected and 0 models loaded, `badgeCount` was correctly 0
-- the glow's `intensity: badgeCount > 0 ? ... : 0` binding was working
exactly as designed the whole time, just correctly showing "Ollama is
idle" rather than "Claude is active." Switched back to `claude` directly
in the state file.

**Cause 2, the real rendering bug, found and fixed independently of
cause 1:** `BioluminescentGlow`'s documented contract is "declare before
`target` in z-order, `target` must fully hide the glow's solid core" --
`AgentIndicator.qml` targeted `background` (the pill), which is exactly
that shape on Minimal (`showBackground: false` collapses the whole
root's implicit size down to `icon.implicitWidth/Height`, so `background`
`.anchors.fill: parent` happens to end up icon-sized there too) but a
much larger `Settings.barInnerWidth` pill on Full/Taskbar -- so the same
glow wrapped a much bigger shape there, sitting BELOW that pill's own
opaque fill in z-order per the documented contract, leaving only a
barely-visible sliver bleeding past the rounded corner. **Confirmed live
this was really imperceptible, not just subtle**, by temporarily forcing
`intensity: 1` (max) on the deployed copy and screenshotting -- still
nearly invisible. This is the actual, literal explanation for "I only
really have seen it on the minimal bar": it isn't that the glow doesn't
render there, it's that Minimal is the one place `background`'s bounds
happen to coincide with the icon's own bounds.

**Real fix, per direct user feedback mid-fix ("the glow itself is around
the PILL and not the agent icon")**: restructured so the glow targets
`icon` directly (tight halo around just the glyph, not the whole pill
footprint) and sits ABOVE `background` but below `icon` in z-order --
a deliberate, scoped departure from `BioluminescentGlow`'s normal
"render below target" contract for this one consumer, so the halo is
visible on top of the background chip instead of hidden behind it. Only
`AgentIndicator.qml`'s own instance changed (`glowBlur: 20`,
`glowSpread: 0.3`, both wider than `BioluminescentGlow`'s shared
defaults of 18/0.06) -- every other consumer (`ActiveWindow.qml`,
`ActiveIndicator.qml`, `Notification.qml`, `HoverPill.qml`) still uses
the component's original defaults/contract unchanged.

**Verified live, both causes, with real screenshots at each step** (not
reasoned about from code): confirmed the pre-fix state showed a
`dns`-glyph icon (Ollama's, not Claude's `smart_toy`) with no visible
halo; after switching the provider back and deploying the restructured
component, a clearly visible teal glow halo renders around a filled
robot icon with a live "2" session-count badge, on the currently-active
Full bar style -- the exact combination that was reported as broken.

## Process wrap-up (2026-08-29): PR workflow fully exercised end to end

PRs #15, #16, #17 all merged into `main` tonight, each through the real
workflow (branch -> commit -> push -> PR -> CI green -> squash-merge),
not just set up and left theoretical. Along the way:

- **Dev VM access set up for real**, not just discussed: SSH key-based
  auth to `10.0.0.26` (alias `aphotic-devvm`), password used exactly
  once to install the key, never stored. See the `reference-dev-vm`
  memory file.
- **Found and fixed a real process/docs conflict before it caused
  confusion later:** `CONTRIBUTING.md`/the PR template still documented
  a `test` -> `main` staging model that recent practice (including
  tonight's own PRs) had already abandoned — `origin/test` was stale,
  confirmed its one commit not on `main` was byte-identical content to
  one already on `main` (same author/timestamp/message/diff, different
  base) before deleting it. Retired via PR #17; `main` is now the single
  PR-gated, CI-enforced branch. Also deleted `origin/features`, another
  fully-merged stale branch found in passing (zero unique commits vs.
  `main`, 81 behind).
- **Dev-VM validation exercised for real on PR #16**, not just described
  in policy: independently reconfirmed the agent-usage PATH bug on a
  second, separate machine, validated the SDDM sync fix and new timer
  unit there too (`systemd-analyze --user verify`, a real
  `systemctl --user start` run, real success), then fully cleaned up the
  test artifacts afterward so the VM's own in-progress work (`test`
  branch checkout with real uncommitted changes) was never touched.
- **The dev-VM-required scope is intentionally narrow**, per explicit
  direction: only `install.sh` changes or systemd-unit changes need it.
  Local Quickshell/QML feature work and other config changes follow the
  normal branch -> PR -> CI-green -> merge flow with no VM step. Saved
  to memory (`feedback-git-workflow`) so this distinction doesn't get
  over-applied in a future session.

`main` is clean: 18/18 tests passing, all CI checks green, branch
protection intact (`enforce_admins: true`, required checks `test`/
`shellcheck`/`bash-syntax`/`CodeQL`).

## Fixed this session (2026-08-29, urgent: real user report)

### 21. install.sh forced nvidia-open-dkms onto machines with an already-installed driver
**Real, external user report** (not found internally): a user with the
proprietary NVIDIA driver already installed and working ran `install.sh`
and found it "annoying" that it tried to install `nvidia-open-dkms` on
top regardless -- they'd started modifying `install.sh` themselves to
work around it. `install_nvidia_driver()` had never checked for an
existing driver at all; it detected the GPU (`lspci`) and always
installed the open driver, with no awareness that `nvidia`/`nvidia-open`
and their `-lts`/`-dkms` variants provide overlapping files, so this
either hit a pacman conflict or silently replaced a driver the user
deliberately chose.

**Fix (PR #19):** new `detect_nvidia_driver_installed()` checks
`pacman -Qq` for any real driver variant before touching anything.
Already installed + interactive: asks keep vs. reinstall. Already
installed + non-interactive with no flag: **defaults to keep** -- the
explicit "should not fail for users" requirement, never touch a working
driver without being told to. New `--nvidia-driver <keep|reinstall>`
flag for scripted installs. `keep` still ensures `nvidia-utils` is
present (separate userspace package, doesn't conflict with either driver
variant, needed by the Dashboard's Performance tab regardless of which
driver the user keeps) rather than skipping the whole function.
`reinstall` uninstalls the existing driver via the AUR helper first,
aborting cleanly if that fails rather than installing on top of a driver
that wouldn't come off.

**Verified:** `bash -n` clean; detection regex checked against every
real driver package name plus several similarly-named non-driver
packages (`nvidia-utils`, `nvidia-settings`, `nvidia-open-beta`,
`libnvidia-container`) confirming no false positives; full function
control flow exercised in isolation with mocked `pacman`/
`install_software`/`AUR_HELPER` across all four paths, each producing
exactly the expected calls with zero real packages touched during
testing. Dev-VM sanity check run on `10.0.0.26` (no NVIDIA GPU there, so
not a full end-to-end repro of the reported scenario, but confirmed
clean `bash -n`, correct `--help` text, and `--dry-run --nvidia-driver
keep` parses and runs through the normal install flow without error).
Fast-tracked per explicit "ASAP" direction -- one scoped PR, not bundled
with the same session's other, non-urgent CLI fixes (item 20 below).

### 20. CLI audit: real bugs found and fixed, per direct request to review all `aphotic` commands
Ran every top-level `aphotic <cmd>` with no args to check for crashes or
surprising behavior. Most showed clean usage/status text as expected;
found two real problems along the way, not by reasoning about the code
but by actually triggering them live:

- **`aphotic shell` (no args) started a SECOND quickshell daemon on top
  of the systemd-managed one already running** -- confirmed live: two
  bars visibly on screen, caught immediately by the user ("You created a
  dual quickshell instance 2 bars are showing"), stray process killed by
  hand. Root cause: `cmd_shell.sh`'s no-arg/`-d` branch started `qs -c
  aphotic` unconditionally with zero check for an existing instance.
  **Fixed:** now `pgrep -f "qs -c aphotic"` first (the same check
  CONTRIBUTING.md already tells contributors to run by hand) and warns
  instead of duplicating if one's already running.
- **`aphotic sddm sync` failed with Permission Denied** even after item
  18's fix made the directory itself sudo-free-writable -- root cause:
  one specific destination file (`tokyonight-...png`) was a leftover
  from an earlier `sudo cp` (root-owned, `644`, no group/other write) from
  before that fix landed. Directory write permission doesn't help when
  `cp` opens an *existing* file for writing -- that needs write on the
  file itself. **Fixed:** `rm -f` the destination first when it exists
  and isn't writable (safe: directory write permission, already
  confirmed, is what actually governs unlink/recreate), self-healing any
  such leftover going forward.
- **`aphotic ai profile <name>` had never worked, ever, on any machine**
  -- it wrote to `ai.activeProfile` in `shell.json` via the generic
  `aphotic_json_set` helper, but the AI Chat panel's real config
  (`activeProvider`/`ollamaModel`/...) lives in a completely separate
  file, `services/ai/AiConfig.qml`'s `~/.config/aphotic/ai-config.json`
  -- confirmed zero consumers of `activeProfile`/`ai-profiles` anywhere
  in the QML tree. The promised "define profiles under .../ai-profiles/"
  directory system was never built either. **Rebuilt for real**: `aphotic
  ai profile <provider>[:<model>]` now validates against the actual
  known provider list (ollama/claude/codex/gemini/chatgpt) and writes
  directly into `ai-config.json` in its own real schema -- `AiConfig`'s
  `FileView` already watches that path, so a running shell picks up the
  change live, same pattern `Themes.qml`/`theme.json` already uses.
  Verified live: set to `ollama:llama3.1:8b`, confirmed both fields
  landed correctly with everything else preserved; set to an invalid
  name, confirmed a clear rejection; restored to `claude` (the real
  active provider on this machine) afterward.
- **`cmd_iso.sh`'s literal "TODO" log line replaced with an honest
  message**, per explicit direction (`iso build` is a genuine future
  feature, months out, not something to imply is close) -- the command
  already failed safely (checks for `mkarchiso`, checks for a real
  archiso profile directory, errors cleanly if either is missing), so
  kept it registered rather than removing/commenting it out, just made
  the "nothing here yet" message honest instead of a bare TODO.
- `restore`/`update`'s no-arg defaults were also audited and confirmed
  genuinely safe by design (`restore`'s default mode is `--populate`,
  explicitly documented as "only deploy files that don't already exist,"
  never overwrites; `update`'s cascade into reload already routes
  through the same `systemctl --user restart aphotic-shell.service` path
  `aphotic reload` uses safely all session) -- not a false-alarm bug,
  just worth confirming rather than assuming after the `shell` finding
  raised the same question about every other command.

## Next up (queued 2026-08-29, after the NVIDIA/CLI-audit fixes): install.sh hardware support is NVIDIA-only

Flagged by the user directly after the urgent NVIDIA-driver-conflict fix
(item 21) shipped: `install.sh` treats NVIDIA as the only GPU vendor that
exists. Verified against the actual script before writing this down, not
assumed:

- **`detect_nvidia()` is the only GPU-vendor detection in the entire
  script.** There is no `detect_amd_gpu()`/`detect_intel_gpu()`
  equivalent at all -- an AMD or Intel-GPU machine just silently never
  enters any GPU-specific setup path, good or bad.
- **No CPU microcode handling whatsoever** -- no `amd-ucode` or
  `intel-ucode` install step anywhere in `install.sh`. This is baseline
  recommended practice on Arch for both vendors (stability/security
  microcode patches applied at boot via the bootloader), and right now
  neither vendor gets it.
- **No AMD/Intel GPU accel driver install path.** `profiles/base/
  full.toml` has `python-pyamdgpuinfo` (a Python binding the Dashboard's
  GPU monitoring already reads from -- see the 2026-08-28 GPU-detection
  fix session), but nothing installs `vulkan-radeon` (AMD) or
  `vulkan-intel` (Intel) the way `install_nvidia_driver()` deliberately
  installs `nvidia-open-dkms` + `nvidia-utils` for NVIDIA. Mesa itself
  likely arrives as a transitive dependency of Hyprland/Wayland
  packages, but the vendor-specific Vulkan ICD does not.
- **`install_software()`'s error handling is a hard `exit 1` on the
  first failed package, full stop.** One renamed/removed AUR package
  anywhere in a profile's package list kills the *entire* install with
  no continue/skip/retry option -- a real, general "should not fail for
  users" gap distinct from (but same spirit as) the NVIDIA-conflict bug
  just fixed. Worth addressing as part of the same hardware-support pass
  since it's the same class of problem: the script assumes a narrow
  happy path and has no graceful fallback when reality doesn't match it.

**Goal, in the user's own words:** "the repo should support both AMD
users and NVIDIA users" (and Intel) -- not narrowed to a specific
component, the general principle that `install.sh` should detect and
handle whatever CPU/GPU vendor combination a real machine has, the same
level of care the NVIDIA path already gets, not fail outright when it
doesn't match the one hardware profile that's been tested. Explicitly
sequenced by the user to happen *after* clearing the rest of that
session's queued items (Media right-click menu, live per-session agent
status, Dock/Minimal bar parity) -- not started yet as of this entry.

## Fixed/added this session (2026-08-29, continued): queued items

### 22. Media right-click: the queued ledger item was stale -- a rich hover popout already existed, only "open the player" was genuinely missing
Went to build the queued "Media right-click context menu (Previous/Next/
Open player)" item and found the premise was outdated before writing any
code: `MediaPopout.qml` (wired into the same hover-popout system every
other bar entry uses, `Config.bar.popouts.media: true` by default)
already has album art, track/artist text, a draggable seek bar,
Previous/Play-Pause/Next buttons, and a multi-player switcher dot row --
everything the queued item asked for except "Open player," and via
hover (lower friction) rather than a right-click menu. Confirmed live in
the file, not assumed from the ledger's own description.

**Real gap, fixed:** right-click on the Media bar icon did nothing at
all (`StateLayer` only ever accepts its default `LeftButton`, so a
right-click reached nothing). Per direct user steer mid-fix -- follow
`AgentIndicator.qml`'s left/right differentiation pattern, but avoid
that component's own "left click opens a static persistent page" shape,
and support real apps generally (not hardcoded to Spotify) -- added:
- `Media.qml`: a `MouseArea` limited to `Qt.RightButton` (doesn't touch
  `StateLayer`'s existing left-click play/pause ripple at all) calling a
  new `openPlayer()`.
- `openPlayer()` first tries to **focus an already-running window**
  matching the MPRIS player's identity, reusing `WindowItem.qml`'s exact
  Hyprland focus-dispatch mechanism (`Hypr.dispatch(...)`,
  Lua-mode-aware). If no matching window exists, **launches the app
  fresh via its real desktop entry**, matched by name against
  `DesktopEntries.applications.values` -- the same source the launcher's
  own app search already reads, not a hardcoded identity-to-binary
  table, so this works for any MPRIS player with an installed `.desktop`
  entry (Spotify, a browser, VLC, etc.), not just one specific app.
  Shows a toast if neither resolves.

**Verified:** clean reload, no QML errors. **Not click-tested against a
real player** -- no MPRIS-exposing player was active on this machine at
verification time (`playerctl -l` -> "No players found", and `mpv`
alone doesn't expose MPRIS without the separate `mpv-mpris` plugin,
which isn't installed here) and no pointer-simulation session was
running this pass. The code reuses two already-proven, unmodified
patterns exactly (`WindowItem.qml`'s focus dispatch, `Launcher.qml`'s
desktop-entry-by-name lookup) rather than inventing new mechanics, but
this is code-reviewed, not click-verified -- worth a real test with an
actual player (Spotify, a YouTube tab, etc.) running next time this
machine is used interactively.

### 23. Live per-session agent status wired up -- verified against this very session's own real hook data
Long-queued gap: `agent_hook.sh` writes `{event, tool, updatedAt}` per
running Claude Code session on every `PreToolUse`/`PostToolUse`/
`Notification`/`Stop` event, but `AgentProviders.qml`'s `sessionLister`
only ever `ls`'d the directory and kept filenames, never reading a
session file's actual content -- real hook work on every single tool
call, for zero effect.

**Fix:** `sessionLister`'s shell command now reads each session file's
content in the same pass (one combined `for f in .../*.json; do ...;
done`, not N separate reads), producing `{id, event, tool, updatedAt}`
objects; `liveSessions` changed shape accordingly (confirmed via grep
this was never read anywhere else, so the shape change is safe).
`AgentPopout.qml` gained a real per-session row list -- icon reflecting
`event` (syncing/check/notification), the tool name, and a running/idle
label.

**Verified end-to-end against real, live data from THIS session --
not a synthetic test.** The Claude Code hook was never actually
configured on this dev machine (`~/.claude/settings.json` had no
`hooks` key at all -- confirmed before assuming it worked). Ran
`configure_claude_code_hooks` for real (the same safe, idempotent
jq-merge `install.sh` already calls, preserves any other tool's hooks
untouched) to wire it up, then watched `~/.local/state/aphotic/
agent-sessions/<this-session-id>.json` update in real time as this very
conversation's own tool calls fired the hook. Opened the agent popout
(`qs ipc -c aphotic call aphotic toggle agent`) and screenshotted:
correctly showed "1 session(s) running," a live "Bash · idle" row, and
the real current token count (3,077,169) -- a genuine live-data
verification of a feature that had never worked on any machine before
this fix, not code review dressed up as testing.

### 24. Dock bar style: closed the "worse than no popouts" parity gap, per a scoped decision
Last of the queued items. Investigated `MinimalIndicators.qml` first and
found its sparse icon set (DND only, no battery/network/bluetooth/VPN)
is a real, deliberate, already-commented design choice ("Toggle-type
indicators only... not continuous status readouts," an explicit
"Omarchy reference" callback) -- not a bug. Presented this to the user
before touching anything; explicit decision: leave Minimal's icon set
alone, only fix Dock (which has no comparable design rationale
documented anywhere) and the real bugs.

**Fixed:**
- `DockBar.qml` gained `handleWheel()` (scroll-to-volume) -- identical
  to Full/Taskbar/Minimal's own, which Dock alone was missing.
- `DockBar.qml` gained a real `StatusIcons` cluster (battery/network/
  bluetooth/VPN/etc., same shared component Full/Taskbar use) --
  Dock was silently dropping this information with no documented
  reason, unlike Minimal.

**Explicitly NOT attempted this pass** (matches the ledger's own prior
"medium lift vs. large lift" split): porting the hover-popout system to
Dock/Minimal. `StatusIcons`' hover flyouts don't work on Dock yet since
Dock has no `checkPopout`/popout-positioning support at all -- given
this exact bar/popout hover mechanism was the subject of a whole 4/4b/
4c/4d/4e/4f investigation earlier this session (one pass of which
shipped a real regression), rushing a port to two more bar styles
tonight was judged too risky for the remaining time budget. Still
tracked as a real, separate, larger feature gap in `docs/ROADMAP.md`'s
Bar section -- unchanged by this fix.

**Verified live**, and worth recording exactly how the verification
almost went wrong: the first two screenshots after switching to Dock
style *appeared* to show nothing at all, and it took checking
`hyprctl layers` (ruling out a crash/zero-size window -- both the
`aphotic-bar` and `aphotic-dock` layer-shell surfaces were present and
correctly sized) before realizing the actual problem was just an
imprecise crop: the dock pill sits smaller and lower than assumed, and
was hidden behind terminal windows in the wide screenshots. A precise
crop at the real expected position confirmed the dock pill rendering
correctly -- app icons, workspaces, the new `StatusIcons` cluster
(wifi/bluetooth icons visible), Clock, and Tray, no QML errors, no
crash. Restored the bar style back to `full` (this machine's normal
setting) afterward.

## Fixed this session (2026-08-29, continued): Dock bar style overlay + right-edge icon clipping

Real user-reported bugs (not code-review finds), both confirmed live via
`grim -o DP-1`/`-o DP-2` before/after screenshots on both monitors after
deploying to `~/.config/quickshell/aphotic/` and `aphotic reload`.

1. **Dock overlaid on top of tiled windows instead of reserving space.**
   `DockWindow.qml` anchored to all four screen edges
   (`implicitWidth/Height: screen.width/height`) with
   `WlrLayershell.exclusionMode: ExclusionMode.Ignore`, so Hyprland never
   reserved any space for it — tiled Kitty windows rendered underneath/
   through the dock pill. Root cause: Wayland's `exclusiveZone` concept
   only has a well-defined meaning for a window anchored to ONE edge (or
   a full-span opposing pair), not a window anchored to all four corners
   at once — `Ignore` was the only mode that made sense for that shape,
   it was never a deliberate "Dock floats over content" design choice.
   **Fix:** restructured `DockWindow.qml` to anchor to only the
   configured docked edge (matching `BarWindow.qml`'s own pattern) with
   a real `WlrLayershell.exclusiveZone: reservedThickness`. The pill
   itself (`DockBar.qml`) still renders centered/floating-looking inside
   that now-edge-spanning strip — no visual change to the pill, just a
   real reservation behind it. Confirmed via `hyprctl monitors -j`:
   `.reserved` went from `[0,0,0,0]` to `[0,0,0,144]` on both monitors,
   and `hyprctl layers`' dock surface shrank from a full `3440x1440`/
   `1920x1080` overlay to a real thin strip.
2. **Power/notification icons clipped and offset off the right edge in
   the horizontal-bottom orientation.** Root-caused via temporary
   `console.log` instrumentation on the deployed copy only (captured
   through `journalctl --user -u aphotic-shell.service`, reverted after):
   `StatusIcons.qml`'s `groupLayout` is a `GridLayout` positioned via raw
   `anchors` (only `anchors.right` active in the horizontal-bar state, no
   opposing `anchors.left`), which — unlike a `GridLayout` actually
   managed by a parent `Layout` — never automatically binds its own
   `width` to its `implicitWidth`. It stayed frozen at a stale, too-small
   value (`40.8`) while its real content width had grown to `286`, so the
   anchor-derived `x` position placed the rightmost icon group outside
   the Dock pill's own rounded boundary. **Fix:** added
   `PropertyChanges { groupLayout.width: groupLayout.implicitWidth }`
   inside the existing `State { name: "vertical"; when:
   Settings.barHorizontal }` block, alongside the existing
   `AnchorChanges`.

Both fixes touch all four dock orientations (top/bottom horizontal,
left/right vertical) since they're driven by the same
`Settings.barHorizontal`/`barPositionBottom`/`barPositionRight`
properties already used elsewhere — only bottom-horizontal was
live-verified this pass (the user's actual config), the other three
orientations are code-reviewed but not separately screenshotted.

Files: `modules/bar/DockWindow.qml`, `modules/bar/components/
StatusIcons.qml`.

### Follow-up, same session: real user report of "the margins are HUGE" caught a THIRD bug the above missed

The user caught this from the live desktop, not a screenshot — the fix
above made the Dock reserve real space (correct), but `hyprctl monitors
-j`'s `.reserved` value came back `144` on both monitors, not the
expected `80` (dockBar's real 64px thickness + 16px edgeMargin) — a
persistent, real 64px dead gap between the dock pill and the true
screen edge, not a rendering artifact.

**Root cause, confirmed via isolation testing (temporarily hardcoding
`WlrLayershell.exclusiveZone` to distinctive constants and diffing
`hyprctl monitors -j` before/after each reload):** `Settings.barSkin`'s
own QML default is `"pill"` (a full-bar skin) until its `FileView` loads
the user's persisted `"dock"` value asynchronously a moment later. In
that startup window, `BarWrapper.qml`'s `hiddenMode` (and therefore
`exclusiveZone`) briefly evaluates as if the bar style were "full", so
`BarWindow.qml` commits a real nonzero `exclusiveZone` (`contentWidth`,
not 0) to the compositor at its very first layer-shell commit — then
correctly flips back to `0` a moment later once Settings loads, which
is what a later live `console.log` check of `barWrapper.exclusiveZone`
showed (a clean `0`), making the bug look fixed from inside QML even
though it wasn't. The transient nonzero commit doesn't reliably shrink
back down afterward once Hyprland has already accounted for it —
confirmed by forcing `BarWindow`'s zone to a literal, non-reactive `999`
and watching `.reserved` track it exactly (`1029 = 999 + 30`), proving
Hyprland sums whatever it was actually sent, not what the QML property
currently reads.

**Fix:** gated both `BarWrapper.qml`'s `exclusiveZone` and
`DockWindow.qml`'s `WlrLayershell.exclusiveZone` on the existing
`Settings._loaded` property (already used elsewhere in `Settings.qml`
for this exact class of "don't act on defaults before the persisted
config loads" problem) — `0` until `_loaded` is `true`, same as
`disabled`/`hiddenMode`. Confirmed via `hyprctl monitors -j`:
`.reserved` now reads the correct `[0, 0, 0, 80]` on both monitors, and
`hyprctl layers -j` shows the dock layer's `y + h` landing exactly flush
with true screen height (`1360 + 80 = 1440` on the 1440-tall monitor,
`1000 + 80 = 1080` on the 1080-tall one) — no more phantom gap.

**Process note, directly from the user:** "We need gates in place to
catch visual changes before they are shipped" and "I need to VALIDATE
any visual changes before shipping with a full screenshot, not zoomed
in or cropped" — going forward, any visual/layout change gets a full,
uncropped `grim -o <output>` screenshot of the affected monitor(s)
shown before it's considered done, not a cropped region chosen by
whoever's verifying it. A cropped/zoomed check is exactly what let this
third bug through the first verification pass in this same investigation.

Files (this follow-up): `modules/bar/BarWrapper.qml`,
`modules/bar/DockWindow.qml`.

### Second follow-up, same session: dock pill is stuck far-left/top, not centered — FIXED (see "Resolution" at the end of this entry)

**Was blocking PR #24; no longer is.** The dock-pill-centering bug described here
has been present in `DockWindow.qml` since the very first restructuring
commit on this branch (`4221cb6`), so it's already sitting in the open
PR, not a new regression from this follow-up. The two earlier follow-ups
above (overlap/clipping fix, reserved-zone fix) are fine and unaffected;
only the centering piece is broken.

**Symptom:** in the dock bar style, the pill (icons cluster) renders
pinned to the far left of the screen in horizontal orientation (bottom
docked, the user's actual config) instead of horizontally centered along
the bar's long axis. Confirmed on both monitors via full uncropped
`grim -o` screenshots — not a cropping artifact, the earlier lesson from
this same session's previous follow-up.

**Root cause #1 (confirmed, real): `root.horizontalCenter` /
`root.verticalCenter` are invalid references.** In `DockWindow.qml`,
`root` is the `id` of the outer `PanelWindow` itself, which is NOT a
`QtQuick.Item` and has no `horizontalCenter`/`verticalCenter` anchor
line. `dockBar`'s original code was:
```qml
anchors.horizontalCenter: Settings.barHorizontal ? root.horizontalCenter : undefined
anchors.verticalCenter: Settings.barHorizontal ? undefined : root.verticalCenter
```
`root.horizontalCenter` silently resolves to `undefined` (QML doesn't
error on this), so the binding is a no-op and `dockBar` falls back to
its default, unanchored `x`/`y`. Every other centered element in this
codebase anchors to `parent` (the window's real content `Item`), never
to a `PanelWindow` id directly — confirmed by grepping every
`horizontalCenter`/`verticalCenter`/`centerIn` usage in the tree, all of
which use `parent`. **The fix for this part is: change both lines to
reference `parent.horizontalCenter`/`parent.verticalCenter` instead of
`root.horizontalCenter`/`root.verticalCenter`.** The same file's other
four edge anchors (`anchors.top`/`bottom`/`left`/`right`, all originally
written as `root.top`/`root.bottom`/`root.left`/`root.right`) have the
exact same bug, but two of the four (`root.top`, `root.left`) happened
to produce the visually-correct result anyway, because an Item's own
top/left edge is always local coordinate 0 — the same value an
unbound/default `x`/`y` falls back to — so it was a coincidental match,
not a working binding. `root.bottom`/`root.right` are NOT 0, so those
two are genuinely broken too (would misplace the pill for a top-docked
horizontal bar or a left-docked vertical bar specifically — margin ends
up on the wrong side).

**Correction — nothing described above is actually committed. Verified
directly against `git log`/the checked-out file just before writing
this note: HEAD is still `e44cd12`, and all six anchor lines (both
center anchors AND all four edge anchors) still read exactly as
originally written, all six using `root.`, none using `parent.`.** An
earlier draft of this note claimed the edge-anchor half was already
committed and pushed; that was wrong — re-verify against `git log` and
a live `grep` of the file rather than trusting that claim. **The
correct, complete fix is: change all six of `dockBar`'s anchor lines in
`DockWindow.qml` (`horizontalCenter`, `verticalCenter`, `top`, `bottom`,
`left`, `right`) from `root.<X>` to `parent.<X>`, together, in one
edit** — don't split it into two edits the way this pass did.

**What actually happened this pass, for the next person's benefit:**
while fixing root cause #1, a `find`/replace-style edit meant to update
just the four edge anchors accidentally replaced the entire six-line
anchors block (center + edge) with only the four edge lines — silently
deleting `anchors.horizontalCenter`/`anchors.verticalCenter` outright
instead of fixing them. Live `console.log` instrumentation on the
deployed copy caught this fast (`dockBar.x` stayed `16` — exactly
`edgeMargin`, not the expected `~1377` center position, and re-grepping
the deployed file for `horizontalCenter` came back with zero matches,
which is what exposed the accidental deletion). That broken
intermediate edit was then reverted wholesale
(`git checkout -- Configs/quickshell/aphotic/modules/bar/DockWindow.qml`,
then redeployed) to get back to a known-consistent state before handing
this off — which reverted the correct edge-anchor fix too, not just the
broken deletion. **Net result: the working tree and the live deployed
copy are both back to the original, fully unfixed `e44cd12` state** (all
six anchors still `root.`, still broken). No debug instrumentation
remains deployed.

**Open questions for whoever picks this up:**
- Why `dockBar.x` measured exactly `16` (== `edgeMargin` ==
  `Tokens.padding.large`) with NO horizontal anchor binding active at
  all, rather than the `0` a totally unbound Item would default to, was
  never resolved — worth understanding before assuming the `parent.`
  fix alone is sufficient, in case something else (a stray margin, a
  `Region`/mask interaction, or a leftover anchor from `DockBar.qml`'s
  own root `Item`) is also contributing. Re-add
  `anchors.horizontalCenter: Settings.barHorizontal ? parent.horizontalCenter : undefined`
  (and the vertical equivalent), redeploy, and re-check `dockBar.x`
  against the expected centered value
  (`(parentWidth - dockBar.width) / 2`) before considering this closed.
- Re-verify the reserved-zone fix (previous follow-up) and the
  overlap/clipping fix (original fix) still hold once centering is
  corrected — none of those should interact with this, but full,
  uncropped screenshots of all four dock orientations (not just
  bottom-horizontal) are still owed regardless, per the existing
  "Queued / open" note below.

**Resolution (2026-08-29, later the same day — fixed, verified live):**
All six of `dockBar`'s anchor lines in `DockWindow.qml` were changed from
`root.<X>` to `parent.<X>` in one edit, exactly as prescribed above. No
other change was needed.

Verified against the running instance rather than by inspection: with a
temporary `console.log` probe on `dockBar` (since removed — the committed
file carries no instrumentation), the deployed shell reported
`x=16 y=201 w=64 h=678 pw=80 ph=1080`. The live config is a **vertical,
left-docked** bar, so that is exactly correct on both axes:
`y == (1080 - 678) / 2 == 201` (the `verticalCenter` binding now resolves
and actually centers), and `x == 80 - 64 == 16` (the `parent.right` edge
anchor placing the pill against root's inner edge, leaving `edgeMargin`
on the docked side). `hyprctl monitors` still reports `reserved [80,0,0,0]`,
so the reserved-zone fix from the previous follow-up is unaffected.

**The open question about "why `dockBar.x` measured exactly 16" is answered
and closed:** 16 is not a mystery value and not a stray margin — it is
`parent.width - dockBar.width` (`80 - 64`), i.e. the *correct* position
produced by the `parent.right` anchor for a left-docked vertical bar. The
previous pass mis-diagnosed it because it reasoned about the symptom as
though the bar were bottom-docked horizontal (where the expected centered
value would have been `~1377`); on the actual vertical config, `x` was
already right and it was `y` — pinned to `0` by the accidentally-deleted
`verticalCenter` anchor — that was wrong. Nothing else contributes to the
pill's position.

**Still owed (unchanged):** full, uncropped screenshots of all four dock
orientations. Only bottom-horizontal and (now) left-vertical have been
looked at; the `top`/`bottom`/`left`/`right` edge anchors are symmetric
and all six lines were fixed together, but top-docked horizontal and
right-docked vertical have not been eyeballed on a real display.

## Agent graph Phase 0 — foundation shipped (2026-08-29, branch `feature/agent-graph-foundation`)

Full detail lives in `docs/FEATURES.md` (decisions, benchmark numbers,
finalized wire format, re-planned phases). Recorded here only so the
ledger stays the one place tracking what actually changed and what is
still owed.

**Both rendering paths were spiked for real, not argued on paper.** Path
(a), the compiled C++ scene-graph plugin, *builds against system Qt 6.11
and imports cleanly into Quickshell 0.3.0 via `QML_IMPORT_PATH`* — so it
stays available as a Phase 3.5 escalation and this is a cost decision, not
a feasibility one. Path (b) won on evidence: JS force-directed layout
benchmarked inside Quickshell's own engine on the slowest target machine
(software-rendered QEMU dev VM) costs 0.40/1.58/3.54/9.04/36.7 ms per frame
at 50/100/150/300/600 nodes. The realistic ceiling (150–300 nodes) is 21%
to 54% of a 16.67 ms budget on the worst hardware anyone runs this on.

**The hook was rewritten and is now 3× cheaper per firing.** 70 ms → 23 ms
measured on the dev VM, because it was spawning three `python3` processes
plus `date` per event and now `exec`s one worker (`agent_hook.py`). This
runs on *every tool call of every session*, so it was worth the pass on its
own merits.

**Two real bugs found while finalizing the wire format, both fixed:**
- `Stop` fires at the end of every assistant *turn*, not at session end.
  The old hook deleted the session file on `Stop`, so it was retiring
  sessions that were still alive. `SessionEnd` now retires them; `Stop`
  marks idle. A 12 h staleness sweep covers installs still on the old
  four-event hook set until they re-run `install.sh`.
- Subagent tool calls fire hooks under the **parent's** `session_id` with
  `agent_id`/`agent_type` attached and nothing naming the `Agent`/`Task`
  call that spawned them. Parentage is therefore a documented heuristic
  (first call for an `agent_id` binds to the most recent running
  `Agent`/`Task` node) — verified working end-to-end against real payload
  shapes, not assumed.

**Hardware tiering is in the foundation, not bolted on later.** Trevin's
own machine (i9-14900K / RTX 4090) will typically be sharing the GPU with a
resident Ollama model, and the same shell runs on software-rendered VMs.
`AgentGraphService.tier` resolves from the detected GPU and demotes one
tier while Ollama holds models loaded — verified live: the dev VM's Virtio
GPU auto-resolved to `lite`. Tiers scale node budget, tick rate and
particle density only; **no tier renders a cheaper-looking graph.**

**Verified live, not by inspection:** a throwaway Quickshell instance
loaded the service against a synthetic event log — 3 sessions, 22 nodes, 28
events ingested; run archive listed and replayed (5 events, 95 ms span);
subagent `Grep` correctly parented to its `Agent` node.

### GPU rendering track promoted the same day
Window-peek thumbnails and shader-driven telemetry stopped being "adjacent
frontier, someday" notes and became a sequenced track with the agent graph:
G1 (shader telemetry, warm-up) → G2 (window peek, low-level buffer/texture)
→ G3 (GPU-native execution graph, QSG/QRhi + compute). Recorded in three
places on purpose — technical scope in `docs/FEATURES.md`, ledger context in
`docs/IDEAS.md`, and a permanent copy in `docs/ROADMAP.md` because
`docs/FEATURES.md` is deleted when the agent graph ships and G3 outlives it.
This does not reverse Phase 0's declarative decision; G3 is where that
decision was always heading, and it waits on the declarative graph being
finished and useful first.

### Still owed on this branch
- No renderer exists yet — Phase 0 is data only. Phase 1 is the first
  visible thing.
- Nothing consumes `AgentGraphService` yet, so its singleton is lazy and
  never instantiated during normal shell startup. That is deliberate for
  now, but it also means the tail process only starts once something binds
  to it — worth remembering when Phase 1 profiles startup cost.
- The hook's new events (`SessionStart`, `PostToolUseFailure`,
  `SubagentStop`, `SessionEnd`) only reach a machine that re-runs
  `install.sh`. Existing installs keep working on the old four.
- Not tested against a *live* Claude Code session on this machine — the
  hooks aren't wired into `~/.claude/settings.json` here (no
  `~/.local/lib/aphotic`), so every payload used was synthetic, built to
  the documented hook schema. First real-session run is owed.

## Agent graph Phase 1 — the graph renders (2026-08-29, branch `feature/agent-graph-render`)

Decisions and checklist state live in `docs/FEATURES.md`. Here: what
actually happened and what the next person needs to not re-learn.

**Both remaining open decisions closed with evidence, not preference.**
Layout: force-directed and radial were both built and run against the same
sample graph. Force-directed **never settled** — 15 nodes, still relaxing
after 15 s, i.e. a 60 Hz loop that never stops, plus every existing node
drifting whenever a new one arrives. Per-frame cost was fine (0–1 ms); the
failure was behavioural, not performance. Radial settles by construction,
costs nothing at rest, and reads as the call tree the data actually is.
**The force-directed path was then deleted, not left behind as a switch** —
reintroducing it later is cheap, carrying dead flexibility is not.
Surface: shipped as a Command Center tab, as originally recommended.

**Two QML traps found the hard way, both now commented in the source:**
- `Repeater` delegates must be `Item`s. `ShapePath` is not one, so a
  `Repeater` of `ShapePath` inside a `Shape` silently draws **nothing** —
  no warning, no error, just no edges. First screenshot showed a graph of
  floating labels with no connections. Edges are now grouped by status into
  three `ShapePath`s fed by `PathMultiline`, which is also three geometry
  nodes for the whole graph rather than one per edge.
- One packet per edge with its own `NumberAnimation` is the obvious build
  and the wrong one. All packets share a single `flowClock`, phase-offset
  by index, so particle count doesn't multiply running animations and the
  clock stops entirely when nothing is in flight.

**Verified visually, not by inspection.** Iterated on real screenshots
through four rounds: no edges → edges but overflowing the surface → fit
normalisation → icons and contrast. The tab itself was opened in the
running shell and confirmed end to end (tab bar entry, header, live tier
chip reading `lite` on this VM, empty state).

### Still owed on this branch
- **Only ever rendered synthetic data.** The sample harness had three
  sessions, a subagent branch, a failed call and an ended session — but
  hooks still aren't wired into `~/.claude/settings.json` on this machine,
  so no frame of this has been drawn from a real Claude Code run. Nodes
  arriving and updating *live* is unproven. That is the single most
  important thing to check next.
- Layout is unproven above ~20 nodes. `maxNodesPerSession` caps at 60–300
  by tier, and the radial ring grows with child count, but a session with
  200 real tool calls has never been drawn.
- No hover, no click-through, no zoom — all Phase 2/2.5.
- `AgentGraphService.layoutHz` is now deliberately unwired: radial has no
  loop to tick. It stays on the service for the physics/native paths. If it
  is still unused when those land, delete it.
- The dashboard tab default was temporarily flipped to `agentGraph` to
  screenshot it and has been flipped back to `dashboard`. Verify that in
  the diff before merging.

## Agent graph Phase 2 — the graph is alive (2026-08-29, branch `feature/agent-graph-alive`)

Decisions in `docs/FEATURES.md`. What matters here:

**State is carried by motion, not by legend.** Running breathes and flows,
waiting holds a steady glow, errored stays marked in the error colour,
ended drops to half opacity and lingers. The glow is the shared
`BioluminescentGlow`, so it inherits the global `depthEffects` tier for
free — which also means state has to stay readable with depth effects OFF.
It does: pill fill, scale, edge weight and packet flow all carry it
independently of the glow.

**Packet speed encodes call age.** Fresh calls stream fast, a call grinding
for 20 s crawls. Implemented as an integer multiplier on the shared clock —
a fractional multiplier looks correct until you notice every packet jumping
at each wrap of the clock.

**`cwd` added to the wire format** so a session node can try to focus its
terminal. Claude Code hooks expose no window or PID, so this is a
best-effort title match on the cwd leaf and it fails silently. Recorded as
a known gap rather than dressed up as a feature.

### Still owed
- Same as Phase 1's headline gap: **still no frame drawn from a real Claude
  Code run.** Everything is the synthetic harness.
- Click-to-focus has never matched a real terminal, because no real session
  has ever written a `cwd` here.
- The tooltip sits directly under the node and can cover a neighbour on a
  dense graph. Fine at demo density, likely annoying at 100 nodes.
- Selection is view-local state — it resets whenever the tab is rebuilt.


## Agent graph Phase 2.5 - zoom and navigation (2026-08-29, branch `feature/agent-graph-zoom`)

Viewport/canvas split: the layout still solves into the viewport's own
size, and zoom/pan is a transform on top, so nothing about the layout had
to learn about zoom. Zoom is toward the pointer, not the centre.

**Detail thinning is a legibility feature, not a perf one.** Tool labels
drop below 0.72x and everything but the pill below 0.42x, because
fixed-size pills at ten sessions turn into unreadable overlap long before
they cost frames. Culling offscreen nodes/particles is the perf half.

### Still owed
- **Wheel, pinch and drag have never been driven by a real pointer.** All
  zoom testing on this branch set `zoom`/`panX` programmatically. The
  handlers are stock, but "stock and untested" is still untested.
- Setting `zoom` directly (rather than through `zoomAt`) anchors at the
  top-left, since `transformOrigin` is `TopLeft`. Fine for the buttons and
  handlers, which all go through `zoomAt`/`frameNode` - worth knowing
  before anything else writes `zoom`.
- No keyboard navigation and no zoom-to-selection shortcut.


## Agent graph Phase 3 — execution replay (2026-08-29, branch `feature/agent-graph-replay`)

The centerpiece works. A finished run replays through the *same* renderer,
with a transport, a scrubbable timeline, and export.

**Replay is a different clock, not a different view — and that is enforced
structurally, not by discipline.** The reducer that folds events into
sessions (`AgentGraphService.applyTo`) is now shared between live ingestion
and replay; the tab only swaps where `GraphView.sessions` comes from. If the
two ever diverge it will be because someone edited the reducer, which is the
one place to look.

**Idle-gap compression is what makes it watchable.** Wall-clock gaps over
1.2 s collapse to 1.2 s. The synthetic test run has a four-minute think in
it and plays in 33 s — measured, not estimated. Without this, replay is
mostly a still image.

**Folding forward is incremental.** Only a backwards seek refolds from the
start; playing forward applies one event per step. A naive implementation
refolds every frame and is O(n^2) over a run.

Verified live: 44-event run loaded from the archive, played at 4x,
21/44 events in about 3.4 s, graph growing as it went, errored node marked,
subagent lane rendering under its parent's time range in the timeline strip.

### Not done, deliberately
- **The "shareable summary" half of export.** JSONL export works; a summary
  format is a design question and was left rather than half-built.
- Replay state is view-local — switching tabs and back loses position.

## New requirements captured this session (2026-08-29)

Both are recorded in full in `docs/FEATURES.md`; noted here so the ledger
stays the single index of what is outstanding.

**1. The agentic stack must be opt-in via `aphotic.toml`, not a default.**
Today `install.sh` wires Claude Code hooks and enables the usage timer
unconditionally. That is wrong for a user who wants a clean daily driver.
Needs a feature-enablement table, `install.sh` honouring it on re-run
(including *removing* what it previously added), profiles as presets over
that same table rather than a parallel mechanism, and the shell hiding the
Agent Graph tab entirely when off rather than showing an empty state.
**Worth doing before the graph is announced anywhere** — "installs hooks
into your settings.json" is something to opt into, not discover.

**2. Licensing/attribution.** SPDX headers (`GPL-3.0-only`) were added to
the modules this workstream introduced, which is what makes a file
self-identifying once copied out of the repo. Three things were left as
Trevin's call and not decided unilaterally: whether to sweep headers across
the whole tree, whether the copyright line should name him rather than
"Aphotic-Hypr contributors", and whether anything warrants terms beyond
GPL-3.0 (a NOTICE requiring visible attribution, or dual-licensing). Adding
or changing license terms is legally significant and effectively
irreversible once released.

## Doc convention change (2026-08-29)

`docs/FEATURES.md` and this file are now append-and-strike-through only.
Nothing gets deleted; completed items stay where they were written, struck
through, so both read as a historical log rather than a to-do list that
rewrites its own past. Completed checklist items in `docs/FEATURES.md` were
retro-fitted with strikethrough when this rule landed — earlier phases had
their text *replaced* before the rule existed, and that history is
unrecoverable since `docs/` is gitignored and was never committed.


## Agentic stack is now opt-in (2026-08-29, branch `feature/agentic-opt-in`)

**The framing in the original request was slightly off, and the correction
matters:** `aphotic.toml` did not need a new `[agentic]` table. It already
carries `[install] layers` with an `ai` entry — the agent stack was simply
never gated on it. Adding a second enablement mechanism would have been
exactly the parallel config system CONTRIBUTING forbids.

What now follows the `ai` layer:
- the `aphotic-agent-usage` timer (and de-selecting `ai` on a re-run
  *disables* it, rather than leaving it enabled from a previous run)
- Claude Code hook wiring — plus a new `remove_claude_code_hooks()` that is
  the exact inverse of the existing upsert: drops only entries pointing at
  this repo's `agent_hook.sh`, preserves every other hook the user has, and
  prunes hook events left with empty arrays. Tested against a settings.json
  holding both an Aphotic entry and an unrelated one.
- the AI Chat and Agent Graph tabs, which are **absent** rather than empty,
  via the new `services/InstallProfile.qml` single source
- `AgentGraphService`'s event tail process, which no longer starts at all

**An absent or unreadable `aphotic.toml` counts as enabled.** Someone
running from a git clone before ever running `install.sh` should get the
shell they cloned, not a silently stripped one. Only an explicit config
turns a layer off.

Verified live: with `layers = ["gaming"]` written to `aphotic.toml`, the
Command Center tab bar showed Dashboard / Performance / Workspaces /
Wallpapers and nothing else. The test file was removed afterwards.

### Still owed
- The bar's own agent module still polls `pgrep` every 5 s regardless of the
  layer. Same treatment needed.
- Profile presets ("everything" / "daily driver" / cherry-pick) still need
  wiring in `profiles/` and the install wizard — the layer mechanism honours
  the choice now, but nothing presents it as a choice.
- README's install section and `docs/AGENT_TRACKING.md` still read as though
  the hook is always wired.


## First live run: hooks wired, and two assumptions broke (2026-08-29)

Hooks are now wired into the real `~/.claude/settings.json` (all eight
events, via the repo's own `configure_claude_code_hooks`, settings backed up
first). The graph drew from a real Claude Code session — the long-standing
"everything is synthetic" gap is closed.

**What real data broke:**

1. **`agent_id` never appeared.** Not on any tool call, not on the `Agent`
   call itself. The wire format claims subagent calls carry
   `agent_id`/`agent_type`; that came from the docs and does not match
   observed behaviour here. The subagent-parentage heuristic therefore has
   nothing to bind to — every call attaches to the session root, and
   subagent branches never form. Unproven, not working. Whether subagent
   tool calls fire hooks at all is still unknown: the test subagent was
   stopped before its own commands ran, so that is not settled either way.
2. **`SessionEnd` fired mid-session**, followed by `SessionStart` with the
   **same session_id**, when the Claude Code process restarted. Phase 0
   moved retirement from `Stop` to `SessionEnd` to stop retiring live
   sessions — the right move, on an assumption that was still too strong.
   Fixed: later events revive an ended session with its history, and pruning
   spares any session whose `updatedAt` is newer than its `endedAt`. The old
   60 s prune window missed destroying this session's history by 0.4 s.

**What held:** session_id stability, `tool_use_id` pre/post pairing,
`duration_ms`, `cwd`, all three sinks, and the no-polling tail feeding a
live graph — 12 real nodes on screen, history preserved across the restart.

**Retroactive correction:** earlier entries called the wire format and
parentage "verified end-to-end". That was against synthetic payloads shaped
to the documentation. Real verification covers the list above and nothing
more.

## Frontier ideas recorded (2026-08-29)

`docs/FRONTIER.md` (gaming telemetry, security topology, eBPF fabric,
GPU-native observability) is cross-referenced from `docs/FEATURES.md` and
explicitly **not scheduled** — nothing there is actionable until the agent
graph is finished and tested. Two connections recorded so they aren't
rediscovered: FRONTIER's three "GPU / Wayland Foundations" are the same
G1/G2/G3 track already planned, and its "Runtime Event Fabric" is a
generalisation of the Phase 0 pipeline rather than new architecture.


## Subagent branches: chased down, and my earlier conclusion was wrong (2026-08-29)

**Retraction first.** The previous entry said `agent_id` never appears on
real events and that subagent parentage might be unreachable. That was
wrong, and the reasoning behind it was bad: the sample contained no subagent
activity at all, because the test subagent was stopped before it ran a
single tool call. Absence of evidence got written up as evidence of absence.

**Method that settled it:** temporarily registered a second hook that just
appends raw stdin to a file — no repo code touched, removed afterwards —
then ran a subagent that actually completed.

**What is true:**
- Subagent tool calls *do* fire `PreToolUse`/`PostToolUse`, under the
  **parent's** `session_id`, carrying `agent_id` and `agent_type`.
  `SubagentStop` carries them too.
- **The real defect was ordering.** `Agent` is async: its `PostToolUse`
  fires with `status: "async_launched"` *before* the subagent's first tool
  call. The heuristic required the most recent Agent node to still be
  **running**, so it never matched. The synthetic harness hid this by
  emitting the Agent's post event after its children — a shape real Claude
  Code never produces.
- **An exact link exists, so the heuristic was the wrong tool anyway.** The
  `Agent` call's `PostToolUse.tool_response` carries `agentId`, the same id
  its subagent's events use. The hook now records it as `spawnedAgentId`
  (with `description` and `resolvedModel`), and the service binds
  `spawnedAgentId → that call's toolId`. The scan survives as a fallback,
  corrected to not require a running node.

Verified live: two subagents, five tool calls, every one parented to the
correct `Agent` `tool_use_id`.

**Density problem, also only visible on real data.** Real sessions cross 30
nodes fast and the single-ring layout overlapped badly. Children now fill
concentric rings, and the fit-to-area scale is clamped at 0.75 — shrinking a
dense graph to fit just converts spacing into overlap, so past that floor it
overflows and pan/zoom takes over. Verified at 37 real nodes.

**Lesson worth keeping:** every wrong call in this workstream came from
synthetic data shaped to documentation rather than captured from the real
thing. Capturing raw payloads took about two minutes and settled in one pass
what two rounds of inference got wrong.


## Docs consolidated into one pick list (2026-08-29)

`docs/BACKLOG.md` is new and is now **the menu**: every open item across
`ROADMAP.md`, `IDEAS.md`, `FEATURES.md`, `FRONTIER.md`, `FRONTIERV2.md`,
`FRONTIERV3.md` and this file, one line each, with an ID. The workflow it
exists for: open a session, say "let's work on a feature", pick an ID, and
that session scopes and implements it. Nothing was deleted from any source
doc — each one gained a pointer header instead, and they keep the long-form
context behind the one-liners.

**Two things the consolidation surfaced:**

1. **`ROADMAP.md`'s own header is wrong.** It claims to be tracked in git
   "so it stays current for anyone working on the repo" — `docs/` is
   gitignored, so every one of these docs is maintainer-local. Corrected in
   place with a note; the real fix (`F-02`) is either un-gitignoring `docs/`
   or moving contributor-facing content to README/CONTRIBUTING.
2. **The agent graph violates the project's own new guiding principle in two
   specific places.** `FRONTIERV2.md`'s "Compositor-First, GPU-When-Justified"
   rule and its zero-polling requirement are adopted as the measuring stick in
   `BACKLOG.md`. The graph passes on seven counts (event tail not polling, one
   schema, single-sourced state, resource-aware tiering, 0.00% CPU idle,
   declarative-before-native) and fails on two: `AgentProviders` still
   `pgrep`s every 5 s (`AGF-07`) and still re-lists a directory every 5 s
   (`AGF-08`), both now backlog items. Frame-aware rendering (`E2-03`) is a
   third, softer gap — particles animate free-running rather than synced to
   the compositor frame.

**Agent UI polish is its own block** (`AGP-01`…`AGP-15`) because the bar for
that surface is explicitly higher than the rest of the shell: it should look
like nothing else in the ecosystem. Fifteen candidate items, listed only —
no design work was done, per instruction.


## Dock icon sizing bug, full branch consolidation onto `test`, hero image swap, release-note banners (2026-08-29)

### Dock: app icons ignored `barCompact`, mismatched every other bar entry
Reported live: "some of the icon highlights and hover over / popout don't
render properly" on the Dock bar style. Root cause, found by comparing
`DockAppIcon.qml`/`DockBar.qml` against every other bar entry
(`StatusIcons.qml`, `Clock.qml`, `Tray.qml`, `TaskbarBar.qml`'s
`TaskItem`): those all size off `Settings.barInnerWidth` (which honors
`Settings.barCompact`, currently `true` on this machine — `48 * 0.85 =
40.8`), but `DockAppIcon`'s `implicitWidth`/`implicitHeight` and the
Dock pill's own cross-axis thickness were hardcoded to the raw
`Tokens.sizes.bar.innerWidth` (48). With `barCompact` on, the app icons
rendered visibly taller than every other cluster in the same row, and
their `HoverPill`/`StateLayer` highlight circles scaled to match — a
real size mismatch, Dock-only (`DockAppIcon.qml` is newer than the rest
of the bar-entry set and never picked up the shared convention). Fixed
both to read `Settings.barInnerWidth`. Real popout support for Dock
(there is none — `DockWindow.qml` never wires a `BarPopouts.Wrapper` at
all, unlike `BarWindow.qml`) was scoped out as a separate, larger
feature per an explicit user decision (`AskUserQuestion` — "just the
highlight fix"), not silently bundled in.

### Full branch consolidation: `test` branch, off `main`, holding everything not yet shipped
User request: get every not-yet-merged agent/agentic branch plus the
above fix onto one throwaway integration branch that can still be
freely committed/amended before any of it goes to `main`. Traced the
actual branch graph first rather than guessing:
- `fix/dock-bar-overlay-and-clipping` (local, tip `e44cd12`) turned out
  to be **fully superseded** — its content (the phantom 64px
  reserved-zone fix, item 24 above) is already inside `main`'s squashed
  PR #24 merge (`4c0be39`), confirmed by diffing the live file content,
  not just commit ancestry (a squash rewrites hashes, so
  `git merge-base --is-ancestor` reports "no" even when the content is
  identical). Correctly dropped from consolidation instead of
  re-merged, which would have produced duplicate-looking conflicts for
  no reason.
- `feature/agent-graph-cleanup` (the terminology/comment cleanup +
  zoom-fix branch from the previous session) was already rebased onto
  current `main` — used directly as the base for `test`.
- The real unmerged work turned out to be five commits stacked on
  remote `feature/config-sync` (built on the *pre-cleanup* agent-graph
  files, with comments and old terminology): opt-in-gating the whole
  agent stack on the installer's `ai` layer, a `SessionEnd`-fires-
  mid-session history-loss fix, the real subagent-parentage fix
  (`spawnedAgentId` binding, replacing a heuristic that never actually
  fired), finishing the opt-in split (bar module, wizard presets), and
  `install.sh --config-only` + a README accuracy sweep. Cherry-picked
  individually onto `test` in dependency order. Two commits
  (`7803a94`, `a61edec`) conflicted, exactly where expected —
  `GraphLayout.qml`/`AgentGraphService.qml`'s comments (cleanup had
  already stripped the old ones; the incoming commit rewrote them) and
  `README.md`'s Roadmap bullet (both sides had touched the same "AI-
  native differentiators" line, for different real reasons). Resolved
  by hand: kept the *code* changes from both sides in every case
  (verified via `git show <commit> -- <file>` against the merged
  result, not assumed), and dropped every reintroduced `//` comment
  from the six no-comments QML files per CONTRIBUTING.md — a non-
  conflicting comment-only hunk can still slip through a clean 3-way
  merge, so this needed an explicit post-merge `grep` sweep, not just
  resolving the flagged conflicts.
- Verified with a clean `qs -c aphotic` reload after each real
  functional step (zero new warnings/errors each time), not just "the
  cherry-pick said no conflicts."
- Branch renamed to `test` and left there, unmerged, ready for further
  commits before it ever touches `main` — per the explicit "outside of
  main... still commit and modify before shipping" instruction.

### Hero preview image: Agent Graph now the front card, not Settings
`README.md`'s `assets/aphotic-preview.png` (the fanned three-card hero
under `## Preview`) had Settings → Appearance as the front, sharp card.
Swapped the front card's *content* only — same Tokyo Night wallpaper,
same Lofi/Gruvbox cards fanned in behind (those two card fragments were
extracted from the existing asset and reused verbatim, not
regenerated) — for a real, live capture of the Agent Graph tab (221
real nodes from this very session, not a mockup), per explicit user
direction to keep "the exact same [composition], just with the new
agentic workflow module as center." Captured on a scratch empty
workspace (`hyprctl dispatch 'hl.dsp.focus({ workspace = 3 })'` — this
Hyprland build uses the Lua `hl.dsp.*` dispatch API, not classic
`hyprctl dispatch workspace 3`) so the shot was clean wallpaper + tab
bar + card with no other windows behind it. One real defect caught and
fixed before finalizing: a stray captured mouse cursor in a flat
wallpaper region, patched with a local Gaussian-blur smooth rather than
a hard clone-stamp (the harder patch left a visible seam against the
gradient). Approved via `AskUserQuestion` before being committed — this
is the README's most visible single asset, worth a checkpoint before
finalizing pixels no one had reviewed yet.

### `aphotic whatsnew`: Hyprland-native release-note banners
New ask, same session: "add hyprland aphotic themed release note
notifications just like Hyprland release notes, delivered the same and
all." Read literally and confirmed against `hyprctl notify --help` —
Hyprland's own release announcements are delivered via its built-in
on-screen compositor banner (`hyprctl notify <icon> <ms> <color>
<text>`), not a desktop-notification-daemon bubble, so that's the exact
mechanism used here too, not a look-alike QML notification.
- New tracked, public-facing `RELEASE_NOTES.md` at repo root — **not**
  `docs/CHANGELOG.md`, which is gitignored/maintainer-local and ships
  to no real user's clone at all. One short entry per version; the file
  says explicitly to keep entries to one sentence, since `hyprctl
  notify` renders unwrapped and a first draft (four sentences) visibly
  clipped off both sides of the monitor in live testing before being
  trimmed.
- New `aphotic whatsnew` command (`commands/cmd_whatsnew.sh`), using
  the already-existing `$APHOTIC_VERSION`/`$APHOTIC_DOTS_DIR`/
  `$APHOTIC_STATE_HOME` globals from `globalcontrol.sh` rather than
  re-deriving repo-root/state-dir paths by hand. State is one
  `last-seen-version` file; a version's banner fires at most once.
- Wired at two trigger points, per the "first after install.sh or next
  fresh Hyprland instance" request: `deploy_user_configs`'s shared
  completion path in `install.sh` (covers both a full install and
  `--config-only`, one choke point), and `Configs/hypr/startup.lua`'s
  `hl.on("hyprland.start", ...)` block (covers a plain `git pull` that
  skipped re-running `install.sh`, and is genuinely free since that
  file is already live-symlinked straight from the repo — no deploy
  step needed for either change to take effect on this machine).
- Real bug caught in testing, not assumed: the first version
  unconditionally wrote `last-seen-version` right after calling
  `hyprctl notify`, regardless of whether the call actually succeeded.
  On a fresh install, `install.sh`'s own call runs *before* Hyprland
  has ever started — `hyprctl` has no compositor to talk to yet and
  fails — which would have silently marked the version "seen" and
  suppressed the one banner a new user would actually see, from
  `startup.lua`, moments later. Fixed to only write the state file
  inside the `if hyprctl notify ...; then` success branch.
- Verified live end-to-end with `aphotic whatsnew --force`: confirmed
  the state file updates only on a real successful notify, and grabbed
  a `grim` capture of the actual on-screen banner (pink/red, matches
  the shell's own accent) before and after trimming the blurb length.

---

## Queued / open

Pulled forward from `IN_FLIGHT.md`'s old "Next up," "Corrections," and
"Dead code and stubs found in passing" sections, plus today's finding
above. Kept here instead of scattered across multiple docs.

### Not yet folded into `docs/ROADMAP.md` / `docs/IDEAS.md`
Verified against the tree; fold these in when those two docs are next
touched, then delete from here.

- **Calendar applet is already shipped.** `IDEAS.md` lists it as "not
  currently in Aphotic"; `modules/dashboard/DashCalendar.qml` is a full
  month grid referenced from `DashboardTab.qml`, `Clock.qml` and
  `SettingsPopout.qml`.
- **Dashboard tabs are already shipped.** `ROADMAP.md`'s "Organize the
  Dashboard into real tabs" is stale —
  `modules/dashboard/DashboardContent.qml:14-19` defines the five tabs
  and `:59-98` is the Loader-per-tab cross-fade the design doc specified.
- **The keybinds cheatsheet is not cheap.** `IDEAS.md` assumes
  `Configs/hypr/keybinds.lua` is "one Lua table to read". It is not — it
  is a sequence of imperative `hl.bind(...)` calls with keys built by
  string concatenation, actions as opaque `hl.dsp.*` calls, and a `for i
  = 1, 10` loop generating 20 binds at runtime. Build it on `hyprctl
  binds -j` at runtime instead, which is both cheaper *and* correct for
  users who edited their own binds.
- **Calculator applet conflicts with a stated non-goal.** `README.md:150`
  lists a calculator among things deliberately left out. Reconcile
  before building it.
- **Dock/Minimal parity is worse than "no popouts".** Picking either
  style also silently deletes the battery, network, bluetooth and VPN
  indicators (`DockBar.qml:207-215`, `MinimalBar.qml:62-85`,
  `MinimalIndicators.qml:23-29` ships one icon), and Dock additionally
  has no `handleWheel`, so it loses scroll-to-volume. Both styles are
  advertised with screenshots and live previews. Split the roadmap item:
  status-icon parity is a medium lift, popouts are a large one (the
  flyout geometry in `popouts/Wrapper.qml` assumes an edge-docked strip,
  so a floating centered pill needs new positioning math).

### Small, well-scoped
- **Media right-click context menu** (new scope, not a bug — see above).
  Lightweight version: `MouseArea`/`TapHandler` with `RightButton` on
  `Media.qml`, a small menu with Previous/Next/Open player, matching the
  Tray/`secondaryActivate()` precedent for "right click = secondary
  actions" already established in this codebase.
- **GPU cycle-button click verified only by code review, not a live
  click** (see above) — worth a real mouse pass whenever this
  environment (or a different one) has pointer simulation available, or
  just eyeballing it by hand once at a real desk.
- ~~Launcher pane centering verified only by code review~~ — **verified
  live 2026-08-29** via the same temporary `currentCategory` default-value
  flip + screenshot convention used for items 11/13/14 this session:
  title + "Results style" group render vertically centered in the pane,
  no dead zone. Closed.
- **Bar popout hover system (items 4/4b/4c/4d/4e/4f): the core bug is
  now live-verified, not just code-reviewed** — 4f's `BarHit.qml`
  contains-test fix was confirmed with a real `ydotool`-scripted sweep
  down the vertical bar's `statusIcons` pill, both before the fix
  (captured the exact wrong resolution: `agent` winning well past its
  own bounds) and after (captured the correct `network → bluetooth →
  vpn → hostinfo` progression), and the user independently confirmed
  live ("Both showed up that time") before any of this was written up.
  This is qualitatively different from every earlier entry in this
  sequence, which shipped on code-review confidence alone — one of
  which (4c) turned out to ship a real regression.
  **Still genuinely open, now that real tooling exists to check it
  properly (`ydotool`, see 4f) instead of guessing:**
  (1) the exact "hover across the gap into the flyout" motion 4e's
  `hoveringFlyout` typo fix targets — the sweep so far only exercised
  hit-testing WITHIN the bar strip, not a cursor crossing from the bar
  into a rendered flyout's own bounds; (2) horizontal bar orientation
  and `TaskbarBar.qml` specifically — the live sweep was vertical-bar,
  `Bar.qml` only; (3) very fast flicks across multiple icons in one
  motion, to see whether `HoverHandler`'s own event-coalescing (4d's
  documented remaining limitation) is a real practical issue or was
  masked by the `BarHit` bug this whole time; (4) the hover-highlight
  pill glow / workspace indicator, to confirm 4d's regression really
  is fully gone and not just "well enough to not be reported again."
  A `ydotool` sweep script covering these, screenshotting each step
  the way 4f's diagnosis did, is now a realistic next step instead of
  more code-only guessing.
- **Dock/Minimal still have no popout system at all** — unrelated to
  the long-hover fix above (different bug entirely), tracked already in
  `docs/ROADMAP.md`'s Bar section; noted here only because it was
  checked and ruled out as in-scope for this pass.
- `Configs/.local/lib/aphotic/agent_hook.sh:30` writes
  `{event, tool, updatedAt}` per session that
  `services/AgentProviders.qml:151`'s `liveSessions` never reads past
  the filename — the Claude Code hook does real work on every tool call
  for zero effect today. Full contract in `docs/AGENT_TRACKING.md` §3.
  This is the exact dependency plugin-system `on_agent_event` (Phase 3)
  is blocked on.
- `Configs/.local/lib/aphotic/commands/cmd_scheme.sh:29` writes
  `scheme.active`, which has no consumer anywhere.
- `Configs/.local/lib/aphotic/commands/cmd_ai.sh:39` and
  `cmd_iso.sh:28-32` both print a literal `TODO` to the user's terminal.
- ~~`components/ScreenState.qml:13-14` — utilities/sidebar dead
  properties~~ — **removed 2026-08-29** (item 15).
- ~~`components/AnchorAnim.qml`, `AnimLoader.qml`, `effects/
  Elevation.qml` dead components~~ — **removed 2026-08-29** (item 15).
- `docs/wiki-pending/cli.md` (now archived, not deleted) still says
  `aphotic shell` is a stub ("IPC passthrough needs real IPC targets")
  — there are 18 real IPC targets today. Worth correcting whenever that
  doc is migrated into the Wiki, not urgent before then.

### Community / needs dedicated testers
- **AMD GPU: need a dedicated tester/contributor for Ollama + AI-assistant
  GPU acceleration. Tracked here 2026-08-29 so it isn't forgotten now
  that this is a community project.** All Ollama/AI-assistant GPU
  support and verification in this repo so far has been done on NVIDIA
  hardware only (see the NVIDIA-only note under "Next up" above re:
  `install.sh` hardware support). AMD's path is different
  (ROCm vs CUDA, `HSA_OVERRIDE_GFX_VERSION` quirks on unsupported/
  newer cards, different Ollama build flags) and untested end-to-end by
  anyone on this project. Needs someone with real AMD hardware to
  validate Ollama GPU acceleration and the AI-assistant pane against it,
  and ideally to drive the `install.sh` AMD support already queued
  above. Good first call-out for the README/CONTRIBUTING "how to help"
  section if one gets added.
- **Gaming mode: free GPU VRAM (kill local Ollama models) before Steam/
  Proton launches. NOT STARTED — requested 2026-08-29, documented here
  per explicit user instruction so it can't go stale/half-implemented
  across sessions.** A locally-loaded Ollama model sitting in VRAM can
  starve a game (or Proton itself) of the VRAM it needs, especially on
  single-GPU setups. Requested shape:
  - A systemd `--user` service/oneshot (or a `cmd_gaming.sh` CLI
    subcommand it calls into) that does a hard `ollama stop <model>` /
    unload sweep — "strict," i.e. don't skip it if a model looks idle,
    always force-unload before proceeding.
  - Triggered before Steam/Proton actually starts — options to weigh
    when this is picked up: a Steam launch-options wrapper script (most
    reliable, works for any title without per-game config), a
    `systemd` path/exec hook on the Steam binary, or a manual keybind
    only. A keybind-only approach doesn't cover "launch a game from
    Steam's own UI" unless paired with the wrapper, so the wrapper is
    probably load-bearing, not optional.
  - A keybind toggle for the mode itself, `SUPER+SHIFT+G` was the
    user's suggested default (or nearest available unbound combo — check
    `Configs/hypr/keybinds.lua` for collisions before landing on the
    final bind) — add via the same `hyprctl binds -j`-driven keybinds
    cheatsheet infrastructure already shipped this session.
  - Needs a decision on scope before implementation starts: kill Ollama
    models only, or also pause/lower-priority other known VRAM
    consumers this project manages (nothing else identified yet as of
    this writing).
  **Process requirement from the user, applies to this item specifically
  and as a standing rule going forward:** this does not get implemented
  piecemeal across sessions and left half-built. When work on this
  starts, it happens on its own `feature/gaming-mode-vram-release`
  branch (or a `fix/`/other clearly-scoped branch name if the shape
  changes), follows the same branch → PR → CI → merge workflow as
  everything else post-viral, and only gets a `README.md` mention once
  it is actually working end-to-end — not before. This entry is the
  place to check for current status; if it's still listed here as "NOT
  STARTED," no code for it exists yet anywhere in the tree.
- **Dock and Minimal bar styles have no hover-popout system at all** —
  `DockBar.qml` never wires up a `popouts` property; `MinimalBar.qml`'s
  `checkPopout` is a literal empty no-op. Full/Taskbar have it. See
  `docs/ROADMAP.md`'s Bar section.
- **`AgentProviders.qml`'s live per-session status is unread** — see the
  dead-hook item above; the concrete next step is `sessionLister`
  reading each session file's `event`/`tool` instead of just listing
  filenames, and `AgentPopout.qml` rendering per-session rows.
- Everything else long-lived stays in `docs/ROADMAP.md`'s Open section
  (Settings panel gaps, theming engine, plugin system Phase 2/3, etc.)
  — not duplicated here.

---

## Verification notes / environment limitations (carried forward)

- **UPDATE (2026-08-29, superseding the note below): `ydotool` is now
  installed and working** (see item 4f above for the full story) —
  pointer simulation in this environment is no longer a hard blocker.
  `ydotoold` needs to be started per-session as root, with
  `--socket-own=<uid>:<gid>` so the actual command-issuing user can
  reach the socket (`sudo ydotoold --socket-own=1000:1000` on this
  machine) — it is not currently a persistent systemd unit, and a
  plain `sudo systemctl enable --now ydotool.service` failed (unit not
  found/configured) the one time it was tried. `YDOTOOL_SOCKET=/tmp/
  .ydotool_socket` must be set in whichever shell issues `ydotool`
  commands (it does not persist automatically between separate Bash
  tool calls in this harness — export it inline in the same command,
  or re-export at the start of a new sweep script). **Coordinates are
  NOT 1:1 with Hyprland's logical pixel space on this machine** — `ydotool
  mousemove -a X Y` empirically maps to logical `(2X, 2Y)` (confirmed
  via `hyprctl cursorpos` probing at several points), despite both
  monitors reporting `scale: 1`; divide target logical coordinates by 2
  before passing them to `ydotool`. This whole capability came from the
  user proactively asking what tooling could let hover/pointer bugs be
  verified for real instead of continuing to guess — worth remembering
  that asking rather than continuing to guess was the actual unblock,
  not a new debugging technique on its own.
- **The note below is now historical** (kept for context on why earlier
  entries in this doc were code-review-only): no pointer or keyboard
  input-simulation tool existed in this dev environment before 4f.
  Confirmed absent at the time: `wtype`, `ydotool`, `dotool`, `wlrctl`,
  `xdotool`. `/dev/uinput` existed and was group-writable, but no Python
  `uinput`/`evdev` binding was installed, and installing one just for a
  one-off check wasn't judged worth the residue at the time. Anything
  needing a real click, hover, drag, or scroll gesture had to be
  verified by a human at the real desk, or via careful temporary
  code-level overrides (e.g. flipping a tab's default value to look at
  it, then reverting) the way the GPU card verification earlier in this
  doc did.
- **`qmllint` on `$PATH` is Qt 5's and is useless** — exits 255 with no
  output on every file including untouched ones. The real binary is
  `/usr/lib/qt6/bin/qmllint`, and even that produces noisy false
  positives on this codebase's singleton pattern. **The reliable check
  is `journalctl --user -u aphotic-shell.service` (or `qs -c aphotic
  log` for a foreground run) after a reload** — and specifically check
  the unit actually came up (`systemctl --user status
  aphotic-shell.service`), not just that the reload command printed ok.
  A crash-loop can silently leave a stale prior instance looking alive
  if you only check for the *absence* of a running `qs` process rather
  than confirming the *current* one is healthy.
- **`~/.config/quickshell/aphotic` is a deployed copy of this repo's
  `Configs/quickshell/aphotic/`, not a live symlink.** See the process
  note under "Fixed this session" #1 above — repeat this warning here
  because it's exactly the kind of thing that wastes a full session for
  the next person if it's only recorded once.


## `AGF-07`/`AGF-08` fixed: `AgentProviders` was the last zero-polling gap (2026-08-30)

Both backlog items from the "Docs consolidated" entry above are done.
`services/AgentProviders.qml` had two 5s timers doing exactly the kind
of busywork `FRONTIERV2.md`'s zero-polling principle rules out:

- `AGF-08` (session lister): every 5s, `ls` the whole
  `agent-sessions/` directory, `cat` every file in it, and overwrite
  every provider's `liveSessions` — for content that only actually
  changes on a hook firing. Deleted outright. `AgentProviders` now
  holds its own `tail -n 400 -F agent-events.jsonl` (a second,
  independent tail of the exact log `AgentGraphService` already reads —
  QML singletons don't share a `Process`, so each keeps its own state
  rather than one importing the other's), parsed incrementally in
  `_ingestSessionEvent` into `_liveByHarness`. Zero polling, presence
  updates the instant a hook fires instead of up to 5s late.
- `AGF-07` (pgrep presence): every 5s, `pgrep -x -c` each of
  claude/codex/opencode regardless of whether any of them had hooks
  wired. Slowed to a 60s **reconcile**, and `_hasLiveEvents` now gates
  it from ever overwriting a harness the event tail has already heard
  from — so with hooks configured (the normal case since Codex's hook
  landed, `9c81b01`/`b4d46be`) `sessionCount` comes from the same
  real-time tail as `liveSessions` above, and pgrep only exists to keep
  section 1 of `docs/AGENT_TRACKING.md`'s "no setup required" promise
  alive for a genuinely hookless machine.

One correctness fix fell out of switching sources: the per-session
`event` field the popout switches on used to be the *raw* Claude Code
hook name (`PreToolUse`, `PostToolUse`, `Notification`) because that's
what `agent_hook.py` wrote into the now-unread `agent-sessions/*.json`
snapshot. `agent-events.jsonl` carries this project's own normalized
names instead (`pre_tool_use`, `post_tool_use`, `notification`, ...) —
`AgentPopout.qml`'s icon/status switch is updated to match, and now also
distinguishes `post_tool_use_failure` (a real "error" icon) where the
old snapshot-based code silently fell through to the default circle.

Verified live, not just read: copied both changed files into the
running `~/.config/quickshell/aphotic` deployment (see the note above —
it's a copy, not a symlink), confirmed via `journalctl --user -u
aphotic-shell.service` that the hot-reload picked them up with no new
warnings (the pre-existing `AiKeys`/`InstallProfile`/`ddcutil` warnings
and one transient `Tokens.rounding` "undefined to double" warning during
reload are unrelated/pre-existing), confirmed the old `pgrep`/`ls`
processes were gone and exactly two `tail -n 400 -F agent-events.jsonl`
processes were running (one per tailer), and screenshotted the actual
open Agent popout on this machine showing "3 session(s) running" with
real per-session rows (a `stop`/idle row, a running `Bash` row) sourced
from this session's own live hook events.
