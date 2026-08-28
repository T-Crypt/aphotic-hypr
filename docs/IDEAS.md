# Aphotic-Hypr — Cross-Project Idea Capture: end4-pC & caffyne-shell

**Purpose:** Review of two external projects for architectural/UX ideas transferable to Aphotic-Hypr, blended against the existing roadmap (README `#roadmap` + `CLAUDE_ROADMAP.md`). This is a capture-and-triage document, not a commitment list — every item below is flagged with a fit assessment against Aphotic's existing architecture and license posture.

**Sources reviewed:**
- [`pctrade/end4-pC`](https://github.com/pctrade/end4-pC) — Quickshell/QML fork of `end-4/dots-hyprland` (illogical-impulse). Same stack family as Aphotic (Quickshell + QML), GPL-3.0. Directly comparable architecture, so most transferable.
- [`caffyne-org/caffyne-shell`](https://github.com/caffyne-org/caffyne-shell) — Fabric/GTK/Python shell, not QML/Quickshell. Different stack entirely, so everything pulled from it is a **UX/architecture pattern to reimplement**, never a port.

---

## 0. Stack & License Notes (read first)

| Project | Stack | License | Portability into Aphotic |
| --- | --- | --- | --- |
| end4-pC | Quickshell + QML, Python color-gen backend | GPL-3.0 (inherits from end-4/dots-hyprland) | High — same rendering engine, same layer-shell primitives, GPL-compatible with Aphotic's own GPL-3.0. Code patterns can be adapted directly (not copy-pasted verbatim without attribution, but architecturally borrowed the way caelestia was).|
| caffyne-shell | (not portable — feature ideas only) | N/A, no code is used | Feature list below is reimplemented from scratch in QML |

---

## 1. Ideas from end4-pC

### 1.1 Theming & Wallpaper Engine
- **Multi-provider online wallpaper integration** — `OnlineWallpapers.qml` pulls from Wallhaven, Unsplash, and Pexels directly in the wallpaper picker, alongside local `Directories.pictures` browsing. Aphotic's Theme Creator/Appearance pane currently only browses local + per-theme wallpaper sets.
  - **Fit:** New capability, not currently roadmapped. Would need its own `services/wallpaper/OnlineProviders.qml` singleton, API-key storage following the existing `ai-keys.json`-style pattern (chmod 600, separate config file), and a new tab/section in the Wallpapers picker (Command Center) or Appearance pane.
  - **Sequencing:** Independent — doesn't block or get blocked by anything in-flight. Good candidate for a self-contained Claude Code delegation later (clear contract, existing sibling patterns for key storage and grid UI).

- **GLSL shader wallpaper transitions** (`Background.qml`) — Peel/circle/Doom/magic-style shader transitions between old and new wallpaper on switch, rendered per-monitor via `PanelWindow`.
  - **Fit:** Visually strong differentiator but higher effort — needs GLSL shader authoring inside QML `ShaderEffect`, plus a fallback path since not all GPUs handle every shader well. This is an **architectural decision**, not a delegate-to-local-model task — flag as Claude/Trevin-only per existing delegation principles.
  - **Sequencing:** Independent of `matugen` work but conceptually pairs with it — worth scoping together since both touch the wallpaper-apply pipeline (`aphotic wallpaper` / `switchwall.sh`-equivalent).

- **Lock-screen theme isolation** — `MaterialThemeLoader` exposes `useLockTheme()` / `useLiveTheme()` so the lock screen can run a *different* wallpaper/palette than the live desktop (`Config.options.background.lockWall`), generated and cached independently.
  - **Fit:** Aphotic's lock screen currently inherits the live theme. This is a small, well-scoped addition — a `lockWallpaper` config key, a second color-gen pass gated on lock-trigger, and a loader-mode toggle in the `Colours` singleton. Good Claude Code delegation candidate (clear contract, existing sibling: the live theme-gen path).

### 1.2 Dock (new surface — Aphotic has no dock today)
- end4-pC ships a bottom-aligned `PanelWindow` dock, separate from the bar, with:
  - Pinned + running-app merging by `appId`, deduped via a `TaskbarApps` service (normalizes IDs lowercase, groups multiple windows of one app into one entry).
  - Reveal logic combining pinned state, hover-to-reveal, "no active toplevel," and fullscreen override (hidden unless hovered when something's fullscreen).
  - Embedded media widget (`DockMedia`) — album art via `curl` + MD5-cached thumbnails, `ColorQuantizer` extracts a dominant color from the art and feeds an `AdaptedMaterialScheme` so the media card self-themes off the album art rather than the wallpaper palette.
  - **Fit:** This is a **net-new surface**, not currently on Aphotic's roadmap at all. Aphotic's Command Center already covers some of this ground (Dashboard media card, Workspaces grid) but a persistent dock is a different UX than an overlay dashboard. Worth an explicit yes/no decision from Trevin before scoping — Aphotic's whole shell philosophy so far is overlay/popout-driven (bar + Command Center + Settings), not a persistent taskbar. Adding a dock is a design-identity choice, not just a feature.
  - If greenlit: reuse the existing `PanelWindow` + `Variants`-per-monitor pattern already used for the bar; the album-art color-quantize idea is a genuinely nice touch worth lifting even if the dock itself is deferred — could apply to the existing Command Center Dashboard media card instead, as a smaller, lower-commitment version of the same idea.

### 1.3 Overview / Window Management (new surface)
- Full-screen "Overview" — search bar + workspace visualization in one `PanelWindow`, two selectable styles:
  - **Grid style** — paginated rows×columns workspace grid.
  - **Niri style** — vertical `Flickable` stack with `getFitScale` logic to scale window previews to fit regardless of aspect ratio.
  - Live window previews via `ScreencopyView`, XWayland indicator badge, compact-mode icon shrinking when previews get small.
  - Unified search: prefix-based mode switching (`!` actions, `:` emoji, `>` terminal commands) inside the *same* overview surface rather than a separate launcher.
  - **Fit:** Aphotic already has a Workspaces grid tab inside the Command Center and a separate prefix-mode launcher (`SUPER+A`) — functionally this overlaps both. The interesting delta is **live screencopy window previews** (Aphotic's Workspaces tab is numbered-grid click-to-jump, not visual previews) and the **fit-scale logic for odd aspect ratios**. Rather than building a whole new Overview surface (redundant with Command Center + launcher), the higher-value move is grafting live `ScreencopyView` previews onto the existing Workspaces tab.
  - **Sequencing:** Independent, moderate effort (new dependency: `ScreencopyView` wiring, likely a new `services/` singleton for per-workspace window enumeration + screencopy handles). Good mid-lift candidate.

- **Keybinds Cheatsheet** — `HyprlandKeybinds.qml` service parses the user's live Hyprland config via a Python script (`get_keybinds.py`) and surfaces it as a searchable list inside the launcher/overview.
  - **Fit:** Directly useful and cheap. Aphotic's keybinds are centralized in `Configs/hypr/keybinds.lua` already (single source of truth, per the README), so a parser is arguably *easier* here than in end4-pC's setup — one Lua table to read instead of scattered bind lines. Strong candidate for the queued low-lift batch (weather widget, color picker, etc.) — could ship alongside them.

### 1.4 AI & Services Layer
- **Multi-provider strategy pattern with function calling** — end4-pC's AI service supports Gemini/OpenAI/Mistral behind one interface, with dynamic system-prompt substitution (`{DISTRO}`, `{WINDOWCLASS}`) and function-calling implemented specifically for Gemini.
  - **Fit:** Aphotic's AI Chat already supports 4 providers (Claude/Ollama/Gemini/ChatGPT) — ahead of end4-pC on breadth. The genuinely new idea is **context-aware system-prompt substitution** (injecting the active window class, distro, etc. into the prompt automatically) and **function calling** as a differentiator. Function calling ties in well with the already-roadmapped "AI chat context injection" open item under AI-native differentiators — worth merging into that workstream rather than treating as separate.
  - **Sequencing:** Function calling is a real scope increase (needs a tool-call contract, likely provider-specific since Claude/Gemini/OpenAI/Ollama all handle it differently) — flag as an architectural decision requiring Trevin/Claude scoping, not a delegate task.

- **Weather via OpenWeatherMap** with GPS-based location (`QtPositioning`) as an alternative to manual city entry.
  - **Fit:** Aphotic's queued low-lift weather widget currently targets Open-Meteo (no API key required — likely the deliberate choice, since OpenWeatherMap needs a key). Worth noting as a **deliberate divergence, not a gap** — Open-Meteo's no-key model fits Aphotic's "honest about what it needs" install philosophy better. Keep Open-Meteo; skip OpenWeatherMap/GPS unless Trevin specifically wants location-based auto-detection later.

- **Package-update notifications** — pacman/yay integration surfaces pending system updates in the About/System settings pane.
  - **Fit:** Aphotic's System pane already has live `aphotic doctor` output and an on-demand package check — this is close to already covered. The delta is making it *proactive* (a badge/notification) rather than on-demand. Small, clean addition to the existing System pane — no new architecture needed.

### 1.5 Overlay / OSD / Utility Panels
- **Persistent overlay widget system** — a `WlrLayer.Overlay` panel hosting draggable, pinnable mini-widgets (crosshair, FPS limiter, sticky notes, recorder indicator, resource meter, volume mixer), with position/size/pin/clickthrough state persisted per-widget to `states.json`.
  - **Fit:** Interesting pattern — Aphotic already has a live resource meter (in bar popouts) and a Pomodoro timer, but they're bar-anchored, not freestanding/draggable. A generalized "persistent overlay widget" *system* is a bigger architectural lift than any single widget — it's really its own feature category (desktop widgets), not a small add-on. Worth scoping as a distinct roadmap line rather than folding into an existing workstream, and it directly overlaps conceptually with the already-planned **movable glowing-orb pet UI** (drag-to-reposition, persistent layer-shell overlay, kill-switch) — same underlying primitive (a persistent, draggable, pinnable `WlrLayer.Overlay` surface with saved position/state). **Recommend building the orb pet's positioning/persistence layer as a reusable "OverlayWidget" base component** rather than a one-off, so future widgets (crosshair, sticky notes, volume mixer) can reuse it later without re-solving drag/pin/persist from scratch. This is a meaningful architecture note for whoever picks up the pet UI plumbing.

- **Desktop right-click menu** with nested submenus (wallpaper carousel inline, "Wallpaper & Style" submenu).
  - **Fit:** Aphotic has no desktop context menu today. Low-to-moderate effort, self-contained, good delegation candidate — reuses existing `Carousel`-equivalent pattern if one exists, or a simple list otherwise. Not currently roadmapped; worth adding to the queued low-lift batch or just after it.

- **Drop Shelf** — a temporary staging overlay for drag-and-dropped files/URIs, with clipboard round-trip (`text/uri-list` via `wl-copy`).
  - **Fit:** Niche but cheap once the overlay-widget base pattern above exists. Low priority — flag as a "nice, not needed" line item, not a roadmap commitment.

### 1.6 Configuration & Settings UI Patterns
- **In-launcher settings search** — typing directly into the main launcher (no `>`/`:` prefix needed) matches against Settings page names *and* section keywords, jumping straight to the right Settings page instead of requiring a separate search box inside Settings.
  - **Fit:** Aphotic's Settings Control Center already has its own searchable category rail — this end4-pC pattern goes a step further by making the *main launcher* double as a settings search, collapsing two search boxes into one. Genuinely nice UX economy. Moderate-low effort: extends `LauncherSearch`-equivalent with a new result type (Settings page/section) and a jump-to-pane action. Good candidate for the low-lift batch or shortly after.

---

## 2. Feature Backlog — pulled from caffyne (implementation-ready, QML-native)

Stripped of anything stack-specific. These are just feature ideas, each written as a standalone backlog item you can hand off or pick up directly.

1. **Drag-and-drop bar/applet layout editor**
   Reorder and place bar modules by dragging them, instead of fixed style presets. Qt Quick supports this natively via `DragHandler` + `DropArea`. Needs: a serialized applet-layout schema (ordered list of module IDs + slot), a layout-edit mode toggle on the bar, drop-target highlighting, and persistence to `~/.local/state/aphotic/settings.json` alongside existing settings. Biggest lift on this list — real scope, but self-contained once the schema is defined.

2. **Applet grouping**
   Let multiple bar modules be visually paired/combined into one cluster (e.g. volume + mic as one pill instead of two). Small data-model addition on top of item 1 — a `group` field in the layout schema, rendered as a joined container. Depends on item 1 existing first.

3. **Uniform `toggle(<name>)` IPC entrypoint**
   One consistent verb for showing/hiding any panel or applet, instead of each surface needing its own bespoke IPC call. Audit current `qs -c aphotic ipc call ...` targets and consolidate around a single `toggle(name)` dispatcher that routes to the right panel's visibility state. Cleans up `keybinds.lua` and makes every future surface auto-bindable with zero new plumbing. Cheap, high-leverage — good to do early since more surfaces (dock, overlay widgets) are coming.

4. **Base16 theme import**
   Add a Base16-format importer to the Theme Creator so users can pull from the existing Base16 scheme ecosystem instead of hand-picking every color. A parser that maps Base16's 16-slot model onto Aphotic's existing palette schema (background/foreground/cursor + 16 ANSI). Self-contained, clear contract — good delegation candidate.

5. **Oklab color interpolation**
   Swap naive RGB/HSV blending for perceptually-uniform Oklab interpolation wherever tonal blending happens in the color-generation pipeline. Makes generated palettes look better at extreme wallpaper colors. Small, surgical change — do this at the same time as wiring `matugen` in, since both touch the same color-math code path.

6. **Per-monitor independent bar settings**
   Let each monitor run its own bar density/style/docked-side instead of one global config applied everywhere. Bar is already `Variants`-per-monitor, so check whether the Settings data model can take a monitor-keyed override on top of the existing global settings (cheap) or needs a schema change (bigger). Investigate first, then scope.

7. **Calendar applet**
   A bar/Command Center calendar view — not currently in Aphotic. Pairs naturally with the existing clock/date settings and Dashboard tab.

8. **Calculator applet**
   Inline calculator accessible from the launcher or a bar popout — quick self-contained addition, no dependencies on anything else.

9. **Process manager applet**
   A lightweight process list/kill-task view, similar in spirit to the existing Performance tab's resource meters but process-level instead of aggregate. Natural extension of the already-shipped live CPU/GPU/memory/disk/network meter.

10. **More shipped color themes**
    Pure content work — expand past the current 8 shipped themes. No architecture change, just asset authoring whenever there's time for it.

---

## 3. Blended & Re-Prioritized Roadmap

Existing roadmap items (from README `#roadmap` and `CLAUDE_ROADMAP.md`) are kept as-is where nothing here changes them. New/merged items are marked **[NEW]** or **[MERGED]**. Nothing here is committed — this is Trevin's triage list.

### Near-term (fits cleanly alongside the current queued low-lift batch)
- Weather widget (Open-Meteo) — *unchanged, already queued*
- Screen color picker — *unchanged, already queued*
- DND/Pomodoro toggle — *unchanged, already queued*
- Wallpaper auto-cycle — *unchanged, already queued*
- Most-used app launcher ranking — *unchanged, already queued*
- Notification quick-toggles row — *unchanged, already queued*
- **[NEW]** Keybinds cheatsheet in launcher (parse `keybinds.lua`, searchable)
- **[NEW]** In-launcher Settings search (jump-to-pane by typing page/section names, no prefix)
- **[NEW]** Desktop right-click context menu (wallpaper carousel + submenu)
- **[NEW]** Uniform `toggle(<name>)` IPC entrypoint — consolidate existing per-surface IPC calls, do this before more surfaces stack up
- **[NEW]** Calculator applet
- **[NEW]** More shipped color themes (content work, no architecture)

### Mid-term (moderate lift, clear contracts — good Claude Code delegation candidates)
- `matugen` as second color engine — *unchanged, already next-up*
- **[MERGED]** Oklab color interpolation — scope together with the matugen work above (same code path)
- **[NEW]** Lock-screen theme isolation (`lockWallpaper` config key, independent color-gen pass)
- **[NEW]** Base16 theme import into Theme Creator
- **[NEW]** Live `ScreencopyView` window previews grafted onto the existing Workspaces tab (not a new Overview surface — extends what's there)
- **[MERGED]** Proactive update-available badge in System settings (extends existing `aphotic doctor`/package-check, not new architecture)
- **[NEW]** Calendar applet
- **[NEW]** Process manager applet (extends the existing Performance tab's live meters)
- **[NEW]** Per-monitor independent bar settings (investigate schema first, then scope)
- Settings panel expansion (Network/Audio/Bluetooth panes) — *unchanged, already roadmapped*
- Plugin system Phase 2/3 (CLI-triggered actions, real UI surfaces) — *unchanged, already roadmapped*

### AI-native differentiators (existing workstream — merged additions)
- Live Agent Activity Module (Claude Code hooks) — *unchanged, already in flight*
- Intelligence popout panel — *unchanged, already in flight*
- llmfit integration — *unchanged, already in flight*
- NVIDIA-gated local Aphotic Assistant — *unchanged, already in flight*
- Movable glowing-orb pet UI — *unchanged, already in flight*, but see architecture note below
- **[MERGED]** Context-aware AI system-prompt substitution (inject active window class, distro, etc. automatically) — folds into the existing "AI chat context injection" open item
- **[NEW, larger]** Function calling for AI Chat providers — flagged as an architectural scoping task (provider-specific contracts), not a quick add

### Architecture notes (not features — decisions/investigations for Trevin)
- **[NEW]** Build the orb pet's drag/pin/persist plumbing as a reusable `OverlayWidget` base rather than a one-off — future draggable overlay widgets (resource meter, mixer, notes) inherit it for free. Worth flagging to whoever picks up the pet UI's model-tiering/plumbing work now, before it's built single-purpose.
- **[OPEN DECISION]** Persistent dock surface (end4-pC-style) — explicit yes/no needed before scoping. Would be a first departure from Aphotic's overlay/popout-only design identity. If "no," the one piece worth salvaging regardless is album-art color-quantize theming for the existing Command Center Dashboard media card.
- **[LARGER, later]** Drag-and-drop bar/applet layout editor (item 1 in the caffyne backlog above) — real scope, do after the near/mid-term batch clears.

### Explicitly declined / not worth pursuing
- OpenWeatherMap + GPS location — Open-Meteo's no-API-key model fits Aphotic's installer philosophy better; keep as-is.
- Drop Shelf (drag-drop file staging overlay) — low value relative to effort; revisit only if the `OverlayWidget` base above gets built for other reasons.

---

## 4. Suggested Sequencing Summary

1. Ship the near-term batch first — cheap, no architecture risk, several are one-sitting additions (calculator, IPC toggle consolidation, keybinds cheatsheet).
2. Scope Oklab interpolation into the matugen work when that starts (same code path — don't do it twice).
3. Do the `OverlayWidget` base-component note *before* or *during* the orb pet plumbing work, since that's already in flight — retrofitting later is more expensive than building it right the first time.
4. Investigate per-monitor bar settings and the dock open-decision whenever there's a natural pause — both just need a quick answer before they can be scoped further.
5. Everything else in the mid-term bucket can be picked off independently as desk time allows, in whatever order fits — none of them block each other.
6. Save the drag-and-drop bar layout editor for last — biggest single item here, worth doing once the smaller wins are already shipped.
