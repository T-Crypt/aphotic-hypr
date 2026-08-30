# Backlog — the pick list

**This is the menu.** Log into a Claude Code session in this repo, say
*"let's work on a feature"*, pick an ID from below, and that session scopes
and implements it. Nothing here is scoped or designed yet — that happens
when an item is picked, not before.

Consolidated 2026-08-29 from `FRONTIER.md`, `FRONTIERV2.md`,
`FRONTIERV3.md`, `ROADMAP.md`, `IDEAS.md`, `FEATURES.md` and `LEDGER.md`.
Nothing was deleted from any of them; this file is the index over them.

---

## How to use this

1. Pick an ID (`AGP-03`, `E3-02`, …).
2. The session reads the linked source doc for whatever context exists,
   then scopes it — branch, plan, open questions surfaced up front.
3. Work lands on its own `feature/*` or `fix/*` branch. Never on `main`.
4. When it ships, strike it through here and write the real entry in
   `LEDGER.md`. Nothing gets deleted from either.

**Effort** is a rough shape, not an estimate: `S` = one sitting,
`M` = a few sittings, `L` = a phase of its own, `XL` = a track.

---

## Document map — what is canonical where

**Consolidated again 2026-08-30** — see
[`APHOTIC_UNIFIED_VISION.md`](APHOTIC_UNIFIED_VISION.md) for the full
picture (architecture, the modular-plugin-system rewrite, per-domain
status, known issues). `FEATURES.md`, `ROADMAP.md`, `FRONTIER-UNIFIED.md`,
and `IN_FLIGHT.md` moved to `archive/` with pointers back into that doc;
nothing was deleted.

| Doc | Role now |
|---|---|
| `APHOTIC_UNIFIED_VISION.md` | **Single source of truth.** Architecture, plugin-system requirements, per-domain (AI/Gaming/Dev/Security) status, known issues, backlog narrative. |
| `BACKLOG.md` (this) | **The pick list.** Every open item, one line each, with an ID. |
| `LEDGER.md` | Historical log — what shipped, what broke, what was corrected. Append + strike-through only. |
| `AGENT_TRACKING.md` | Contract doc for the agent event pipeline. |
| `PLUGIN_SYSTEM.md` | Contract doc for the plugin system. |
| `archive/FEATURES.md` | The agent-graph workstream's own spec and phase log. Complete; kept as history. |
| `archive/ROADMAP.md` | Long-form context behind backlog items, plus the shipped-architecture summaries. |
| `archive/FRONTIER-UNIFIED.md` | Working note unifying the old FRONTIER dumps as one list, sorted by core-vs-plugin delivery shape. Not an index of backlog IDs. |
| `archive/IN_FLIGHT.md` | Older per-batch working notes. Superseded by `LEDGER.md`; kept for history. |

One correction worth knowing:

- `docs/` is now git-tracked again (un-gitignored 2026-08-30) — it's the
  project's durable memory and lives in version control like everything
  else. The earlier "docs/ is gitignored, maintainer-local only" note
  that used to live here and in `ROADMAP.md` is no longer true.

---

## The principle everything is measured against

From `FRONTIERV2.md`, adopted as the project's overarching rule:

> **Compositor-First, GPU-When-Justified** — minimize RAM, CPU, IPC,
> allocations, polling, redraws and GPU utilization. GPU/RHI/QSG techniques
> are used because they reduce overhead or enable something otherwise
> impossible, never because GPU rendering looks impressive.

### How the agent graph (just built) measures against it

Recorded here because the user asked whether the new work fits the
direction. Mostly yes, with two concrete violations already in the backlog
below.

| Principle | Agent graph | |
|---|---|---|
| Zero-polling | `tail -F` + `SplitParser`, no timer | ✅ |
| One event pipeline, many consumers | One schema, three sinks, two renderers | ✅ |
| State deduplication | Single-sourced `AgentGraphService`, shared reducer for live + replay | ✅ |
| Resource-aware degradation | Hardware tier, demotes while Ollama holds VRAM | ✅ |
| Dirty-region / idle cost | Radial layout settles by construction — **0.00% CPU at 55 nodes idle** | ✅ |
| GPU when justified | Declarative first, native path proven but deliberately deferred to G3 | ✅ |
| **Zero-polling (the bar half)** | `AgentProviders` still `pgrep`s every 5 s and re-lists a directory every 5 s | ✅ fixed 2026-08-30, see `LEDGER.md` |
| Frame-aware rendering | Particles/glow animate free-running, not synced to compositor frames | ❌ `E2-03` |

---

# A. Agent system — finish and polish

The graph shipped across `FEATURES.md` Phases 0–4. What remains splits into
visual polish (`AGP-*`), functional gaps (`AGF-*`) and held decisions
(`AGH-*`).

## A1. Agent UI polish — "nothing seen before"

The bar for this surface is explicitly higher than the rest of the shell:
it should look like nothing else in the Hyprland ecosystem. These are
candidate work items, not designs.

| ID | Item | Effort |
|---|---|---|
| `AGP-01` | **Node materials with real depth** — gradient fills, inner shadow, elevation so nodes read as objects rather than flat pills. | S |
| `AGP-02` | **Per-session identity colour** — each concurrent session gets its own accent derived from the theme, so two sessions are distinguishable at a glance without reading labels. | S |
| `AGP-03` | **Arrival choreography** — a new node grows out of its parent along the edge instead of appearing in place. Completion and error get their own exit/settle motion. | M |
| `AGP-04` | **Edge as a living material** — gradient along flow direction, thickness or turbulence carrying duration, not just a stroked line. | M |
| `AGP-05` | **Focus mode** — hovering or selecting a subtree dims everything else, so a 60-node graph can still be read one branch at a time. | S |
| `AGP-06` | **Session heartbeat** — the session root pulses with real activity rate rather than a fixed rhythm. | S |
| `AGP-07` | **Collapse / clustering** — long sessions summarise runs of completed calls into one node ("+12 Bash") that expands on click, instead of silently truncating at the tier cap. | M |
| `AGP-08` | **Parallax depth on pan** — edges, nodes and particles move at slightly different rates, giving the graph physical space. | S |
| `AGP-09` | **Minimap / overview inset** when zoomed past ~1.5×, with a draggable viewport rect. | M |
| `AGP-10` | **Empty state that is alive** — the idle surface should look intentional and animated, not a grey icon and two lines of text. | S |
| `AGP-11` | **Tooltip placement** — currently sits directly under the node and can cover a neighbour at density. Needs collision-aware placement. | S |
| `AGP-12` | **Errored node affordance** — click to read the actual `tool_error`, which the hook does not record yet (pairs with `AGF-04`). | S |
| `AGP-13` | **Replay transport polish** — scrub preview, keyboard shortcuts (space / ← / →), and a clearer play-head on the timeline strip. | S |
| `AGP-14` | **Session root detail** — model badge, elapsed time, call count, and token/cost if the usage data can be joined to it. | S |
| `AGP-15` | **Bar agent popout refresh** — the popout still renders the old three-field snapshot; it now has tool ids, durations, subagent types and statuses available. | S |

## A2. Agent system — functional gaps

| ID | Item | Effort | Source |
|---|---|---|---|
| `AGF-01` | Shareable run summary on export (JSONL export works; the summary half was never built). | M | `FEATURES.md` Phase 3 |
| `AGF-02` | Replay position is view-local — switching tabs loses it. | S | `LEDGER.md` |
| `AGF-03` | Wheel / pinch / drag have never been exercised by a real pointer; all zoom testing was programmatic. | S | `LEDGER.md` |
| `AGF-04` | Hook does not record `tool_error` from `PostToolUseFailure`, so an errored node cannot show why. | S | new |
| `AGF-05` | No keyboard navigation on the graph (tab between nodes, zoom shortcuts). | M | `FEATURES.md` 2.5 |
| `AGF-06` | Subagent parent fallback path is unexercised — the exact `spawnedAgentId` link always wins in practice. Decide whether to keep or delete the fallback. | S | `LEDGER.md` |
| ~~`AGF-07`~~ | ~~`AgentProviders` polls `pgrep` every 5 s.~~ Fixed 2026-08-30 — event-tail-driven, pgrep demoted to a 60s no-hook-only reconcile. See `LEDGER.md`. | M | `FRONTIERV2` |
| ~~`AGF-08`~~ | ~~Session lister re-lists a directory every 5 s.~~ Fixed 2026-08-30 — replaced by the same `agent-events.jsonl` tail `AgentGraphService` already holds. See `LEDGER.md`. | S | `FRONTIERV2` |
| `AGF-09` | Layout unproven above ~60 nodes; tier caps at 60–300 and the ring layout has only been seen at 55. | S | `LEDGER.md` |
| `AGF-10` | `AgentGraphService.layoutHz` is deliberately unwired (radial has no loop). Delete it or wire it when a physics path lands. | S | `FEATURES.md` 1 |

## A3. Held — decisions, not implementation

| ID | Item |
|---|---|
| `AGH-01` | ~~README: add the graph to the module table + roadmap line. Held until the branches merge and you decide it is public.~~ **Merge gate satisfied** — the graph merged to `main` via PR #29 and shipped at v1.2.0. README's Preview/Roadmap already reference it (``GRAPH-verified 2026-08-30``); the module-table row is still absent. Now actionable: add the Agent Graph row to the Quickshell Shell module table. |
| `AGH-02` | README install section: state that the `ai` layer writes hooks into `~/.claude/settings.json`. Arguably a consent disclosure rather than a feature announcement — your call which. |
| `AGH-03` | Sweep SPDX headers across the whole tree, or keep them only on the novel modules. |
| `AGH-04` | Whether the copyright line names you specifically rather than "Aphotic-Hypr contributors". |
| `AGH-05` | Whether anything warrants terms beyond GPL-3.0 (a `NOTICE` requiring visible attribution, dual-licensing). Legally significant, effectively irreversible once released. |

---

# B. Small — ready to pick now

| ID | Item | Source |
|---|---|---|
| `B-01` | Launcher grid: no left/right keyboard navigation (`GridView` already exposes the methods). | ROADMAP |
| `B-02` | Launcher grid: hard cap of 12 results with no pagination or "+N more". | ROADMAP |
| `B-03` | Launcher grid polish — centering/margins, and the browser-vs-shell font unification ask. | ROADMAP / LEDGER |
| `B-04` | `aphotic theme list` — swatch thumbnails instead of text-only. | ROADMAP |
| `B-05` | Notification quick-toggles row inside the Notification Center itself. | IDEAS |
| `B-06` | Wallpaper auto-cycle — timer or systemd unit over the existing `SUPER+W` path. | IDEAS |
| `B-07` | More shipped colour themes (pure asset authoring, no architecture). | IDEAS |
| `B-08` | `theme.toml`'s `[overrides]` table is parsed but consumed nowhere. | ROADMAP |
| `B-09` | Proactive update-available badge in System settings. | IDEAS |

---

# C. Medium

| ID | Item | Source |
|---|---|---|
| `C-01` | **Dock/Minimal hover-popout system** — neither bar style has one at all. Real feature work. | ROADMAP |
| `C-02` | Notification app-icon resolution against installed desktop entries. | ROADMAP |
| `C-03` | Aphotic-branded template for shell-originated notifications. | ROADMAP |
| `C-04` | matugen as a second colour engine, with Oklab interpolation scoped into the same pass. | ROADMAP / IDEAS |
| `C-05` | Settings: Widgets tab; sidebar module; system-updates action; theme-palette swatch view. | ROADMAP |
| `C-06` | Per-monitor independent bar settings (schema investigation first). | IDEAS |
| `C-07` | Live `ScreencopyView` window previews grafted onto the Workspaces tab — the cheap version of `D-02`. | IDEAS |
| `C-08` | Process manager applet extending the Performance tab. | IDEAS |
| `C-09` | System monitor component (processes, PID, CPU, RAM, GPU) in the Settings glass UI. | ROADMAP |
| `C-10` | Screen recorder (`wf-recorder` + existing region select). | ROADMAP |
| `C-11` | Notification grouping. | ROADMAP |
| `C-12` | Lock-screen media controls. | ROADMAP |
| `C-13` | AI chat context injection (active window class, distro) + session handoff widget. | ROADMAP |
| `C-14` | Git status bar module; build/test status OSD; code-aware clipboard history. | ROADMAP |
| `C-15` | Plugin system Phase 2 — CLI subcommand dispatch for plugins. | PLUGIN_SYSTEM |
| `C-16` | `OverlayWidget` base component, built *before* the orb pet needs it. | IDEAS |
| `C-17` | Lock-screen theme isolation (`lockWallpaper`, independent colour pass). | IDEAS |
| `C-18` | Base16 theme import into the Theme Creator. | IDEAS |

---

# D. Big rocks — the GPU rendering track

Sequenced; each rung pays for the next one's infrastructure. Full write-up
in `FEATURES.md` and `ROADMAP.md`.

| ID | Item | Effort | Depends on |
|---|---|---|---|
| `D-01` | **G1 — Shader-driven telemetry materials.** Live telemetry as shader uniforms on bar/panel surfaces. Establishes the `.qsb` pipeline and contributor build step. | L | nothing |
| `D-02` | **G2 — True window-peek thumbnails.** `wlr-screencopy` → live `QSGTexture`. The hard part is DMA-BUF import, format negotiation, frame sync and lifetime. First compiled C++ module shipped to users. | XL | `D-01` |
| `D-03` | **G3 — GPU-native execution graph.** The agent graph re-rendered with `QSGGeometryNode`/`QSGMaterial`, instanced geometry, layout on `QRhi` compute. Feasibility already proven in Phase 0. | XL | `D-01`, `D-02`, agent graph finished |
| `D-04` | Drag-and-drop bar/applet layout editor. Biggest single non-GPU item; explicitly last. | L | — |
| `D-05` | Plugin system Phase 3 — third-party QML panes, needs a stable API subset and real trust/sandboxing decisions. | L | `C-15` |
| `D-06` | Security baselines (`recommended` / `max` profile tiers) with the real per-tool exception design the `exploit-*` layers need. | L | — |

---

# E. Frontier — long range

Consolidated from `FRONTIER.md`, `FRONTIERV2.md` and `FRONTIERV3.md`.
**None of this is scheduled.** It is here so picking from it is possible
without re-reading three idea dumps.

## E1. Compositor-native core (from V2)

The architectural spine everything else in this section assumes.

| ID | Item |
|---|---|
| `E1-01` | **Compositor-native state fabric** — derive shell state from Hyprland/Wayland events instead of polling. |
| `E1-02` | **Zero-polling desktop state** — replace every remaining poll with Wayland/Hyprland IPC/netlink/inotify/udev events. |
| `E1-03` | **Shared event bus** — one pipeline feeding every component instead of each widget querying independently. |
| `E1-04` | **State deduplication layer** — one authoritative state, only changed values distributed. |
| `E1-05` | **Reactive compositor graph** — windows/workspaces/monitors/layers as a graph that updates on state change only. |
| `E1-06` | **Native window lifecycle tracking** — create/destroy/focus/move/fullscreen/title from events, not tree re-queries. |
| `E1-07` | **Unified Linux event collector** — compositor + kernel/userspace events in one normalized model. |
| `E1-08` | **Aphotic Runtime Event Fabric** — the generalisation of all of the above. **The agent pipeline built in `FEATURES.md` is the working prototype to generalise from**: one JSON-line schema, append-only rotating tail, idempotent reducer, durable archive, replay clock. |
| `E1-09` | Live workspace topology — workspaces/windows as compositor objects with spatial relationships, not lists. |
| `E1-10` | Compositor-native window transitions — animate around compositor state changes rather than animating representations. |
| `E1-11` | Monitor-aware shell composition — topology, scale, refresh rate, VRR, position, workspace assignment from compositor state. |
| `E1-12` | Layer-shell spatial awareness — components that understand the real layer-shell hierarchy instead of treating the bar as an isolated app. |
| `E1-13` | Compositor event replay — record and replay workspace/window transitions for debugging and config development. (Same replay shape the agent graph already ships.) |
| `E1-14` | Process relationship graph — ancestry, resource ownership, sockets, files, services as queryable relationships, no constantly refreshed process table. |
| `E1-15` | Native network event stream — netlink/socket events instead of repeatedly invoking networking utilities. |
| `E1-16` | Filesystem event fabric — event-driven notifications instead of recursive scans. |
| `E1-17` | Hardware event fabric — udev/device events for hotplug, GPUs, displays, audio, peripherals. |

## E2. Performance discipline (from V2)

| ID | Item |
|---|---|
| `E2-01` | Adaptive update scheduling — inactive components slow down, active visualizations speed up only when needed. |
| `E2-02` | Dirty-region rendering — redraw on state change only. |
| `E2-03` | Frame-aware rendering — sync expensive updates to the compositor frame lifecycle. |
| `E2-04` | Zero-copy data paths between Wayland, Qt and the render layers. |
| `E2-05` | CPU/GPU workload budgeting — explicit budgets per component, enforced. |
| `E2-06` | Progressive rendering complexity — plain rendering by default, shaders only where they earn it. |
| `E2-07` | Resource-aware degradation under system pressure. (The agent graph's hardware tiering is the first instance of this pattern.) |

## E3. Developer flavours (from V3)

The strongest single pillar in the frontier set: *the shell as the missing
physical layer around the IDE*, not another IDE.

| ID | Item |
|---|---|
| `E3-01` | **Development flavour engine** — detect the active project ecosystem and expose purpose-built surfaces for it. The parent of everything below. |
| `E3-02` | Web surface — live viewport, HMR/dev-server state, breakpoints, build errors. |
| `E3-03` | Frontend component observatory — live preview of the component being edited (React/Vue/Svelte/QML). |
| `E3-04` | iOS surface — live simulator preview, SwiftUI canvas, device matrix. |
| `E3-05` | Android surface — form factors, densities, themes, emulator targets. |
| `E3-06` | Rust surface — Cargo/build state, diagnostics, tests, benchmarks, running binaries. |
| `E3-07` | C/C++ surface — build/debugger state, memory, threads, symbols, tests. |
| `E3-08` | Game development surface — live viewport, frame-time, GPU/CPU, asset loading. |
| `E3-09` | Embedded surface — boards, serial output, flash/debug state, GPIO, hardware telemetry. |
| `E3-10` | DevOps/infrastructure flavour — Terraform, Kubernetes, Ansible, Docker, Proxmox, CI/CD cockpit. |
| `E3-11` | Security development flavour — process, socket, filesystem, container, eBPF telemetry alongside code. |
| `E3-12` | AI development flavour — inference telemetry, tokens/sec, context usage, VRAM, tool execution, multi-agent graph. **Partially exists already** — the agent graph is its execution-visualisation half. |

## E4. Gaming (from V1)

| ID | Item |
|---|---|
| `E4-01` | Frame-time vision — CPU/GPU/VRAM/compositor/VRR/latency as one live performance topology. |
| `E4-02` | Desktop game radar — everything affecting a running game, spatially. |
| `E4-03` | Adaptive gaming HUD surfaces — shader surfaces responding to frame time, thermals, VRR, jitter. |
| `E4-04` | Live workspace/window teleportation — GPU-native previews of whole workspaces (shares `D-02`'s foundation). |
| `E4-05` | Per-game environment engine — deterministic per-game profiles for refresh rate, VRR, audio routing, notifications, shell presentation. |
| `E4-06` | GPU capture timeline — rolling history correlating frame time, utilization, VRAM, compositor events for post-hoc stutter analysis. |

## E5. Security (from V1 + V2)

| ID | Item |
|---|---|
| `E5-01` | Live security topology — interfaces, processes, sockets, routes, services, containers, VMs, users, remote hosts. |
| `E5-02` | Process → network reality map. |
| `E5-03` | Socket observatory — listening ports, TCP state transitions, DNS, bandwidth, owning processes. |
| `E5-04` | Filesystem activity heatmap. |
| `E5-05` | eBPF event fabric feeding the unified rendering layer. |
| `E5-06` | Host change visualization — baseline vs current. |
| `E5-07` | Container / VM security map. |
| `E5-08` | Security flight recorder — rolling black box, scrub backward through the event chain. **Direct sibling of the agent graph's execution replay**; same shape, different event source. |
| `E5-09` | Local security state engine — continuously updated state instead of repeated scanner runs. |
| `E5-10` | Event-driven threat surface — sockets/processes/services/privileges/mounts/users as events. |
| `E5-11` | Minimal-overhead audit mode — capture only high-value security events, no continuous deep inspection. |
| `E5-12` | On-demand deep inspection — baseline stays extremely light; expensive inspection only when the user investigates something. |

## E6. The overarching vision

| ID | Item |
|---|---|
| `E6-01` | **GPU-native observability layer for Linux** — the desktop as a programmable real-time representation of what the system, compositor, GPU, applications, infrastructure and AI workloads are actually doing. Five pillars on one runtime: Gaming, Security, Development, Infrastructure, AI. |

---

# F. Tooling / meta

| ID | Item | Source |
|---|---|---|
| `F-01` | Claude Code wrap-up skill that queues a wrap-up + next-steps request before session usage runs out. | `FRONTIER.md` |
| `F-02` | Fix `ROADMAP.md`'s stale "tracked in git" claim, or un-gitignore `docs/`. | this file |
| `F-03` | Fold `IN_FLIGHT.md` into `LEDGER.md` and retire it as an active doc. | doc hygiene |
| `F-04` | `agent_usage.py` sums only the first matching transcript — should sum every transcript modified today. | AGENT_TRACKING |
| `F-05` | Dead `"unsupported"` availability branch in `AgentPopout.qml` — wire real detection or drop it. | AGENT_TRACKING |

---

## Done

See `LEDGER.md` for the full log. Recent, in order: Dock bar fixes,
agent graph Phases 0–4 (foundation, render, alive, zoom, replay), SPDX
tagging, and the agentic opt-in split.

**Agent graph — verified complete & committed 2026-08-30.** Cross-checked
`FEATURES.md` against `origin/main`: every module it specifies is on `main`
(`modules/agentgraph/GraphView|GraphLayout|GraphReplay|ReplayBar`,
`modules/dashboard/AgentGraphTab.qml`,
`services/ai/AgentGraphService.qml`, `agent_hook.{py,sh}`); VERSION is
`1.2.0`; commit `4392bb8` reads "Bump to 1.2.0: Agent Graph, whatsnew, and
opt-in agent stack warrant a minor, not a patch." Phases 0–3.5 are all
marked DONE in `FEATURES.md` and are present on `main`. Phase 4's two
README items were held pending merge; that gate is now satisfied (see
`AGH-01`), which is the only remaining follow-up. `FEATURES.md` stays as
the historical spec/log per its own append-and-strike-through rule.
