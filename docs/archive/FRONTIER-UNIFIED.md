> **Archived 2026-08-30.** Its conclusions (new plugin capability tags, Phase 3 QML-surface note, frontier-vs-core split) are folded into [`docs/APHOTIC_UNIFIED_VISION.md`](../APHOTIC_UNIFIED_VISION.md)'s Modular Plugin Architecture and Backlog sections. Kept here as the full analysis.

# Frontier — Unified View

A single consolidated list of `FRONTIER.md`, `FRONTIERV2.md`, `FRONTIERV3.md`,
cross-checked against `README.md` and the current design docs. Its purpose is
twofold: (1) present every frontier idea as one flat index, and (2) say, for
each, whether it is a *clear* candidate for the `PLUGIN_SYSTEM.md` concept or
is really core architecture that plugins would ride on instead.

> Status: working note. `docs/` is gitignored (see `BACKLOG.md`'s "Document
> map" correction), so nothing here reaches contributors; this is
> maintainer-local planning.

## Headline

`FRONTIER.md` (V1) dumped **six pillars of a GPU-native observability layer**:
Gaming, Security, the existing GPU/Wayland foundations, plus a unified
direction. `FRONTIERV2.md` added the **compositor-native, zero-polling
architecture** it must be built on, and contributed the project's overarching
rule (Compositor-First, GPU-When-Justified — already adopted in `BACKLOG.md`).
`FRONTIERV3.md` narrowed to the **Development pillar**: the shell as the
"missing physical layer around the IDE," delivered as one runtime whose
flavors react to the detected project.

Their shared thesis, restated once: **five domains (Gaming | Security |
Development | Infrastructure | AI) all backed by the same lightweight
compositor-first event/rendering architecture.** That is the same "one
runtime, many surfaces" claim `OPT-IN-FEATURES.md` and `PLUGIN_SYSTEM.md`
already make — which is why most of the frontier is *not* new work so much as
the destination of work already in flight.

`BACKLOG.md` §E already folds all three into IDs (`E1`–`E6`). The unified list
below re-presents those same items grouped by **delivery shape**, which is the
axis that matters for the plugin question: *core architecture* vs.
*plugin-shaped deliverable*.

---

## Unified index

### Core architecture — frontier items that are NOT plugin material

These are the substrate. They cannot be a plugin (a directory + `plugin.toml`
+ hook scripts firing at a call site); they are the infrastructure plugins are
written *against*. Building them as plugins would mean a plugin must own
process-global state, GPU pipelines, or IPC primitives — the exact inversion
of the "drop a folder in the right place" plugin contract.

| Frontier item | Source | Why not a plugin |
|---|---|---|
| Composition-native state fabric / zero-polling / shared event bus / state dedup / reactive compositor graph / lifecycle tracking (E1-01…E1-06) | V2 | The event substrate the hook-firing loop itself should eventually consume. A plugin fires *because of* a state change; it doesn't own the event fabric. |
| Unified Linux event collector / Aphotic Runtime Event Fabric (E1-07, E1-08) | V1+V2 | `E1-08` is explicitly "generalise the agent pipeline" — a core substrate, not a deliverable. |
| Performance discipline whole group (E2-01…E2-07) | V2 | Cross-cutting rendering/scheduling policy. No plugin owns "the shell redraws only on dirty regions." |
| Shader-driven telemetry materials / GPU-native execution graph / true window-peek (V1 foundations; D-01/D-02/D-03) | V1 | The D GPU track. Native C++/`QSGMaterial`/QRhi work, the explicit inverse of a shell-script plugin. |
| Live workspace/window teleportation, compositor-native window transitions (E4-04, E1-10) | V1+V2 | Built on the D-02 screencopy/C++ foundation; core. |
| The overarching vision — GPU-native observability layer for Linux (E6-01) | V1 | Meta-goal, not an item. |
| Development flavour *engine* (E3-01, the parent) | V3 | Detection + dynamic surface loading = core profile/state mechanics (`OPT-IN-FEATURES` puts the state machine in core, domain logic in plugins). |

### Plugin-shaped — frontier items genuinely worth stringing into `PLUGIN_SYSTEM.md`

These map onto the plugin model cleanly because `OPT-IN-FEATURES.md` already
established the pattern: **core keeps the shared primitive, each domain ships
as a plugin** (see its "what lives in core vs. what's a plugin" table). They
divide into three legs:

**1. Already partially served by shipped plugin hooks** — these want existing
capabilities extended, not invented:

| Frontier item | Source | Plugin reality today |
|---|---|---|
| Per-game environment engine (E4-05) | V1 | `game-theme` is literally "call the existing `on_theme_change` hook + wallust pipeline" (OPT-IN `3.2`). The per-game profile storage/lifecycle is new, but the *trigger* is a plugin capability. |
| Game → theme integration (E4-05 half) | V1 | `on_theme_change` already ships and OpenRGB proves the mechanism. |
| Project-as-profile / agent-context-handoff (E3 dev pillar) | V3 | `on_project_open` already ships (`direnv` is the reference plugin); agent-context-handoff is a new `ai`-category plugin pending `on_agent_event` (Phase 3). |

**2. New capability tags worth adding to the manifest** — the honest way to
"string frontier into the plugin concept" is to add concrete capability tags
for those that are otherwise plugin-shaped but have no trigger yet:

| Frontier item | Source | Candidate capability |
|---|---|---|
| Desktop game radar / frame-time vision / gaming telemetry (E4-01, E4-02, E4-03, E4-06) | V1 | `game-hook` (fire on game process exec/exit — event-driven, matching the zero-polling rule and `OPT-IN`'s `game-discovery`). Telemetry collection stays a plugin; the *trigger* is the capability. |
| Per-game environment engine (E4-05, if not a pure theme hook) | V1 | `game-hook` + workspace/notification state apply. |
| Socket observatory, process→network reality map (E5-02, E5-03) | V1 | `security-hook` (fire on a security-relevant event, e.g. new listening socket / privileged process — event-sourced per `E5-09`/`E1-14`). |
| Host change visualization / security flight recorder (E5-06, E5-08) | V1 | Flight recorder wants the shared ring-buffer primitive in core (`OPT-IN` §4.2) plus a `security-hook` trigger; host-change is a plugin *consuming* the event fabric, not owning it. |
| Live iOS / Android / web / component preview surfaces (E3-04, E3-05, E3-02, E3-03) | V3 | Plugin-owned **QML surfaces** — this is `PLUGIN_SYSTEM` Phase 3 (dynamic QML panes), not a shell-script hook. The right place is the Phase 3 design pass, once the stable API subset exists. |
| Rust / C/C++ / embedded / game / DevOps / security / AI dev surfaces (E3-06…E3-12) | V3 | Same: Phase 3 QML surfaces behind a `dev`/`security`/`ai`-category plugin. |
| AI dev flavour (E3-12, agent execution visualization) | V3 | Largely **already built** — the Agent Graph is the execution-visualisation half (BACKLOG E3-12 notes this). The plugin polish is `on_agent_event` (Phase 3) letting an `ai` plugin subscribe to the graph's event stream. |

**3. The Security pillar's place** — `E5-09…E5-12` (local security state
engine, event-driven threat surface, audit modes, on-demand deep inspection)
are the compositor-native *version* of `E5-01…E5-08`. Their event-sourced
state engine is core (same shape as `E1`); what a plugin can deliver is the
*visualization + a `security-hook` trigger* on top of it. This mirrors exactly
how the AI pillar split: the agent pipeline/event fabric is core, the graph
surface and provider adapters are what shipped as features/plugins.

---

## The honest summary

- **Of the ~50 frontier items, the clear plugin candidates are narrow and
  all funnel through the same gateway:** a small set of new capability tags
  (`game-hook`, `security-hook`) and the already-sketched Phase 3 (plugin-owned
  QML surfaces + `on_agent_event`). Everything else — the event fabric,
  zero-polling discipline, the GPU rendering track, the flavour *engine* — is
  core, and *is already partially built* (agent pipeline = `E1-08` prototype).
- **The items that "won't be a clear match" for `PLUGIN_SYSTEM.md` aren't
  misfits, they're the foundation the plugin concept rests on.** Forcing them
  in would break the "plugin = directory + manifest + hook script" contract.
- **What is genuinely worth stringing into `PLUGIN_SYSTEM.md`** is not the
  whole frontier but three concrete additions, each already precedented:
  1. the `game-hook` and `security-hook` capability tags (same shape as the
     shipped `theme-hook`/`project-hook`/`workspace-hook`),
  2. a Phase 3 note that the Dev-pillar surfaces are exactly the QML-pane
     deliverable already deferred there,
  3. explicit reuse of the shipped `on_theme_change`/`on_project_open` hooks
     by the gaming/dev pillars rather than new parallel mechanisms.

`OPT-IN-FEATURES.md` is the document that already does most of this bridging
in prose; what it lacks is the manifest-level capability tags and the Phase 3
surface design that would make those pillars *actually ship as plugins*.

---

## IDEAS capture — folded in

The following were captured from an external-idea triage pass and are folded
into the unified list here, stripped to their standalone feature shape. They
sort onto the same core/plugin axis everything above uses.

### Core additions (shared primitives / architecture)

- **`OverlayWidget` base component** — build any persistent draggable,
  pinnable, click-through layer-shell surface (orb pet, resource meter,
  mixer, sticky notes) on one reusable base that owns drag/reposition/pin/
  persistence to state, rather than a one-off pet UI. A core primitive the
  frontier's plugin-shaped QML surfaces (Dev-pillar previews, gaming HUD
  surfaces, socket observatory) would ride on.
- **Persistent overlay widget system** — the generalisation of the above:
  freestanding mini-widgets (crosshair, FPS limiter, recorder indicator,
  volume mixer, resource meter) on a persistent layer-shell overlay with
  per-widget position/size/pin/click-through persisted to disk. Not a
  single widget — a feature category.
- **Drag-and-drop bar/applet layout editor** — reorder and place bar
  modules by dragging (`DragHandler` + `DropArea`), driven by a serialized
  applet-layout schema (ordered module IDs + slot), a layout-edit mode,
  drop-target highlighting, persisted to settings. With a small follow-on:
  **applet grouping** (a `group` field joining modules into one pill, e.g.
  volume + mic).
- **Uniform `toggle(<name>)` IPC entrypoint** — one verb to show/hide any
  panel or applet instead of bespoke per-surface IPC, so future surfaces
  (dock, overlay widgets, plugin panes) auto-bind with zero new plumbing.

### Plugin-shaped additions (map to the Phase-3 surface model / existing taxonomy)

- **In-launcher settings search** — the main launcher doubles as Settings
  search, jumping straight to a matching pane (no separate search box).
- **Keybinds cheatsheet** — a searchable list of the user's live keybinds
  surfaced in the launcher, built on `hyprctl binds -j` at runtime (not
  parsing the imperative Lua source).
- **Desktop right-click context menu** — wallpaper carousel + nested
  submenus.
- **Calculator applet** — inline calculator from launcher or bar popout.
- **Process manager applet** — process-level list/kill view extending the
  existing Performance tab's aggregate meters.
- **Base16 theme import** — map Base16's 16-slot model onto Aphotic's
  palette schema in the Theme Creator.
- **Lock-screen theme isolation** — independent wallpaper/palette for the
  lock screen vs. the live desktop (`lockWallpaper` key, second color-gen
  pass).
- **Multi-provider online wallpaper integration** — pull live from remote
  wallpaper hosts in the picker, with API-key storage following the
  existing `ai-keys.json` pattern — or deliberately skip in favor of the
  no-key local pool (a divergence, not a gap).
- **GLSL shader wallpaper transitions** — peel/circle-style shader
  transitions between wallpapers on switch, per-monitor, with a fallback
  for GPUs that can't handle every shader.
- **Live `ScreencopyView` window previews on the Workspaces tab** — the
  cheap version of G2's true window-peek, worth shipping on its own; G2
  replaces the backend later.
- **Album-art color-quantize theming** — extract a dominant color from
  media art and self-theme the card off it rather than the wallpaper
  palette, applied to the Dashboard media card.
- **Proactive update-available badge** in System settings (extends the
  on-demand package check).

### AI workstream additions (fold into the existing AI-native workstream)

- **Context-aware prompt substitution** — inject the active window class,
  distro, etc. into AI prompts automatically (merges with the "AI chat
  context injection" roadmap item).
- **AI provider function calling** — provider-specific tool-call
  contracts; flagged as an architectural scoping task, not a quick add.

### Explicitly declined

- **GPS-based weather location** — the no-API-key weather model fits the
  install philosophy better; keep as-is.
- **Drop Shelf (drag-drop file staging overlay)** — low value relative to
  effort; revisit only if the `OverlayWidget` base gets built for other
  reasons.
