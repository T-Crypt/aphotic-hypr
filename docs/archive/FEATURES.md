> **Archived 2026-08-30.** Agent Graph's own phase-by-phase spec/log, fully shipped. Condensed into [`docs/APHOTIC_UNIFIED_VISION.md`](../APHOTIC_UNIFIED_VISION.md)'s AI domain section. Kept here as the detailed historical record.

# Agent Graph — working spec

> **Consolidated 2026-08-29.** Open work from this file now also appears in
> [`BACKLOG.md`](BACKLOG.md) — the single pick list used by "let's work on a
> feature" sessions (section A). Nothing here was deleted; this file keeps the
> long-form context behind those one-line entries.

Ephemeral planning doc — same lifecycle as CLAUDE_PLUGIN_ECOSYSTEM.md. Delete once
Phase 4 ships and fold a condensed summary into CLAUDE_ROADMAP.md.

## Doc convention (added 2026-08-29)

**Nothing is ever deleted from this file or from `docs/LEDGER.md`.** Completed
work stays where it was written and gets struck through, so both files read as
a historical log of what was planned, what shipped, and what changed course —
not as a to-do list that quietly rewrites its own past. New scope is appended;
superseded scope is struck through with a line saying what replaced it.

## Purpose

This is the working spec for a single feature: a live, GPU-rendered visualization
of concurrent Claude Code agent sessions as a node graph — not another status icon,
a real scene-graph-level rendering of tool-call activity as it streams in from hooks.
No Hyprland or Quickshell shell has built anything like this. It is the flagship
differentiator layered on top of the already-scoped Live Agent Activity Module.

**How to use this doc:** when Trevin says "continue feature changes" (or similar,
with no further detail) in a Claude Code terminal session in this repo, that means:
read this file top to bottom, find the first unchecked task in the earliest
incomplete phase, and implement it. Do not ask which phase — the checklist state
*is* the answer. Open technical decisions are called out explicitly below; resolve
them yourself and record the resolution + rationale in the PR description, not in
conversation.

---

## Hard rules (inherited, non-negotiable)

- Static `PanelWindow` geometry only — no animated anchors/margins/x/y/exclusiveZone.
  Any new surface this feature adds uses the caelestia static-window +
  `offsetScale` content-transform pattern.
- Single-sourced singleton for all new shared state (`AgentGraphService` — see
  Phase 0). No consumer keeps its own copy of graph/session state.
- No comments in QML or shell scripts (CONTRIBUTING.md).
- Reuse existing `SettingsRow`/`SettingsGroup` conventions for any new Settings UI.
- Atomic state file writes for anything persisted to disk.
- Every phase is its own `feature/agent-graph-<phase-name>` branch. Nothing merges
  to `test` or `main` unattended — stop and hand back control before merging.
- Commits within a phase stay separable per sub-feature for independent
  revertability.
- **Hardware tiering is mandatory, and it never touches the look.** The
  same shell runs on a software-rendered dev VM and on an i9-14900K/RTX
  4090 workstation, and on the latter it is very likely sharing the GPU
  with a resident Ollama model. Tiers scale *how much is simulated and how
  often* — node budget, layout tick rate, particle density — never the
  visual language. No tier renders a flatter, cheaper-looking graph; a lite
  machine gets the same Aphotic treatment with fewer things moving in it.
  `AgentGraphService.tier` is the single source for this (see Phase 0).
- Nothing simulates while nothing is on screen. `surfaceVisible` gates the
  layout loop, and the loop settles to zero work when the graph stops
  moving. A physics loop spinning behind a closed panel is exactly the
  "resources wasted for looks" this feature must not be.
- The `on_agent_event` hook wire format defined here is the same one the Live
  Agent Activity Module bar indicator consumes. One event pipeline, two renderers
  (bar summary + graph). Do not fork the schema.

---

## Open decisions (resolve in Phase 0, document choice in PR description)

1. **Rendering approach — RESOLVED 2026-08-29: path (b), stay declarative.**
   Both paths were spiked for real before choosing, per this doc's own rule.
   - **(a) Companion C++ plugin — proven possible, deliberately not taken.**
     A minimal `QQuickItem` with a real `updatePaintNode`/`QSGGeometryNode`
     override was built against system Qt 6.11 with cmake+ninja and then
     *actually imported by Quickshell 0.3.0* via `QML_IMPORT_PATH`
     (`SPIKEA-IMPORT-OK`). So path (a) is available as a Phase 3 escalation
     and is not an architectural dead end — but taking it now would put a
     compile step (and Qt 6 dev headers) into install.sh for every user, and
     it does nothing for the VRAM-contention problem that actually matters
     on the target hardware.
   - **(b) Declarative — chosen.** JS-side force-directed layout was
     benchmarked in Quickshell's own QML engine on the *slowest* target
     (a software-rendered QEMU dev VM), naive O(n²) all-pairs repulsion:
     50 nodes 0.40 ms/frame, 100 nodes 1.58 ms, 150 nodes 3.54 ms,
     300 nodes 9.04 ms, 600 nodes 36.7 ms. Against a 16.67 ms budget the
     realistic ceiling from this doc (5–10 sessions, dozens of live nodes)
     lands at 150–300 nodes — 21% to 54% of budget on the worst machine
     anyone will run this on, and far cheaper on the 14900K. The escape
     hatch when that isn't enough is algorithmic (node budget, Barnes-Hut)
     before it is architectural.
   - Edge/node *materials* stay ordinary QML + `Shape`/`ShapePath` for now.
     `qt6-shadertools` (the `qsb` compiler) is **not** installed on the
     target machine and no repo shader pipeline exists today; `.qsb` files
     would be a committed build artifact plus a contributor-only dep. That
     is a fine trade later for a specific effect — it is not a prerequisite
     for shipping, so it is not being taken on in Phase 0.
2. **Layout algorithm — RESOLVED 2026-08-29 (Phase 1): radial call tree.**
   Both were built and run against the same sample graph, then one was
   deleted rather than left behind as a switch.
   - Force-directed (Fruchterman-Reingold, parent springs, centre pull)
     **never settled** — 15 nodes, still `settled=false` after 15 s of
     relaxation, i.e. a 60 Hz loop that runs forever. Per-frame cost was
     tiny at that size (0–1 ms), so this isn't a performance failure, it's
     a behavioural one: a permanently-running simulation is exactly the
     "resources burned for looks" the hard rules forbid. It also drifts
     every existing node whenever a new one arrives, which on a graph that
     updates several times per second reads as constant jitter.
   - Radial won: one pass, settles immediately, **zero steady-state cost**,
     and an arriving node doesn't disturb the nodes already placed. It also
     reads correctly as what the data actually is — a call tree. Nodes
     animate to their new positions with the existing `Anim` curves, so
     insertion still feels alive rather than snapping.
   - Ring radius scales with child count, and the whole result is
     normalised into the available area, so the surface is size-agnostic.
3. **Where the graph surface lives — RESOLVED 2026-08-29 (Phase 1):
   Command Center tab.** Shipped as `modules/dashboard/AgentGraphTab.qml`,
   reusing the existing tabbed-dashboard scaffolding exactly as the original
   recommendation suggested. The renderer itself
   (`modules/agentgraph/GraphView.qml`) takes `sessions` as a property and
   knows nothing about tabs, so promoting it to its own `SUPER+`-bound
   surface later is a re-host, not a rewrite.

---

## Wire format (shared with Live Agent Activity Module) — FINALIZED

Verified against the Claude Code hooks reference on 2026-08-29 rather than
assumed. What the hook payloads actually give us, and what mattered:

- `tool_use_id` **is** present on both `PreToolUse` and `PostToolUse`, so
  pre/post pairing is a real correlation, not a guess by ordering.
- `PostToolUseFailure` carries `tool_error` — errored status is observed,
  not inferred from a missing post event.
- `duration_ms` is on `PostToolUse` — node duration is free.
- Subagent tool calls fire hooks with the **parent's** `session_id` plus
  `agent_id`/`agent_type`. There is no field naming the `Agent`/`Task` call
  that spawned them, so parentage is derived (see below).
- No event carries a timestamp; the hook stamps its own.
- `SessionStart`/`SessionEnd` exist. `Stop` fires at the end of every
  assistant turn, **not** at session end — the old hook deleting the
  session file on `Stop` was retiring sessions that were still alive.

`Configs/.local/lib/aphotic/agent_hook.sh` (a thin `exec` wrapper) and
`agent_hook.py` (the whole worker, one process per event instead of the
four the old script spawned — measured 70 ms → 23 ms per hook firing on the
dev VM) emit one JSON object per line:

```json
{"v":1,"sessionId":"...","event":"pre_tool_use","status":"running","timestamp":"2026-08-29T16:57:04Z","t":1788022637252,"tool":"Bash","toolId":"toolu_01","agentId":"ag_9","agentType":"Explore","durationMs":42}
```

`event` is one of `session_start | pre_tool_use | post_tool_use |
post_tool_use_failure | notification | stop | subagent_stop | session_end`.
`t` is epoch ms — the ISO `timestamp` is second-resolution and several tool
calls land inside one second, so ordering and replay use `t`.

Three sinks, one schema, no forks:
- `~/.local/state/aphotic/agent-events.jsonl` — the live stream, rotating
  (512 KB → last 1000 lines). What the shell tails.
- `~/.local/state/aphotic/agent-sessions/<session_id>.json` — the existing
  bar snapshot, byte-compatible with what `AgentProviders.qml` already
  reads. It is literally a projection of the last event, not a second
  schema. Deleted on `session_end`; a 12 h staleness sweep covers installs
  still wired to the old event set.
- `~/.local/state/aphotic/agent-runs/<session_id>.jsonl` — durable
  per-run archive, capped at 25 runs × 2 MB. The live log is a tail by
  design, so **execution replay reads this**, not that.

**Parentage is a documented heuristic, not a claimed guarantee:** the first
tool call seen for an `agent_id` binds to the most recent still-running
`Agent`/`Task` node in that session, and later calls from the same
`agent_id` inherit that binding. Verified end-to-end against real payload
shapes — a subagent `Grep` correctly attached to its parent `Agent` node.

## Corrections from the first live run (2026-08-29)

Hooks were wired into a real `~/.claude/settings.json` and the graph drew
from a real Claude Code session for the first time. Three things the
synthetic harness could never have caught:

1. ~~**`agent_id` did not appear on a single real event**~~ — **this was
   wrong, retracted the same day.** The sample it was drawn from contained
   no subagent activity at all: the test subagent was stopped before it ran
   a single tool call, so of course nothing carried `agent_id`. Raw payload
   capture plus a subagent that actually completed settled it — see
   "Subagent parentage, settled" below. Subagent tool calls **do** fire
   hooks and **do** carry `agent_id`/`agent_type`, exactly as documented.
2. **`SessionEnd` is not proof a session is over.** A real session emitted
   `SessionEnd` and then `SessionStart` with the **same `session_id`** when
   the Claude Code process restarted mid-session. Phase 0 moved session
   retirement onto `SessionEnd` specifically to fix `Stop` retiring live
   sessions — that move was right, but the assumption behind it was still
   too strong. Fixed: any event after `session_end` revives the session with
   its history intact, and pruning no longer drops a session whose
   `updatedAt` is newer than its `endedAt`. The old 60 s prune window would
   have destroyed the history here by 0.4 s.
3. **Everything else held.** `session_id` stability, `tool_use_id` pre/post
   pairing, `duration_ms`, `cwd`, all three sinks, and the no-polling tail
   into a live graph all behaved exactly as designed on real data.

### Subagent parentage, settled (2026-08-29, real payloads)

Raw hook payloads were captured by temporarily registering a second hook
that just appended stdin to a file — no repo code involved, removed
afterwards. What that showed:

- Main-session `PreToolUse` carries `cwd`, `effort`, `hook_event_name`,
  `permission_mode`, `prompt_id`, `session_id`, `tool_input`, `tool_name`,
  `tool_use_id`, `transcript_path`. No `agent_id` — correct, since the docs
  scope that field to subagents.
- A subagent's own tool calls **do** fire `PreToolUse`/`PostToolUse` under
  the **parent's** `session_id`, carrying `agent_id` and `agent_type`.
  `SubagentStop` carries them too.
- **The real defect was ordering, not missing data.** `Agent` is async: its
  `PostToolUse` fires (`status: "async_launched"`) *before* the subagent
  makes its first tool call. The old heuristic looked for the most recent
  **still-running** `Agent`/`Task` node, and by then the Agent node was
  already `completed`, so it never bound. Two synthetic-data assumptions
  hid this: the harness emitted the Agent's post event after its children.
- **And there is an exact link, so no heuristic is needed.** The `Agent`
  call's `PostToolUse.tool_response` contains `agentId` — the same id its
  subagent's events later carry. `agent_hook.py` now records it as
  `spawnedAgentId` (plus `description` and `resolvedModel`), and
  `AgentGraphService` binds `spawnedAgentId → that call's toolId` on close.
  The old scan survives only as a fallback, corrected to not require the
  Agent node to still be running.

Verified live: two subagents, five tool calls between them, every one
parented to the correct `Agent` `tool_use_id` in the real graph.

### Density, found only by running it for real

Real sessions pass 30 nodes quickly, and at that size the single-ring layout
overlapped badly. Two fixes, both invisible on the 15-node synthetic sample:
children now fill **concentric rings** instead of one growing ring, and the
fit-to-area scale is **clamped at 0.75** — shrinking a dense layout to fit
just converts spacing into overlap, so past that floor the graph overflows
the surface and pan/zoom does the rest. Verified at 37 real nodes.

**Retroactive honesty note:** earlier entries in this file described the
wire format and parentage as "verified end-to-end". That verification was
against synthetic payloads shaped to the documentation, which is weaker than
it sounded. Only items 3 above are verified against real hook output.

## Phased roadmap

### Phase 0 — Foundation (branch: `feature/agent-graph-foundation`) — DONE 2026-08-29
- [x] ~~Resolve Open Decision 1 (rendering approach) with a throwaway~~
      prototype, not just a design doc. Both paths spiked; numbers and
      outcome recorded under Open decisions above.
- [x] ~~Define/finalize the shared `on_agent_event` wire format; confirmed it~~
      satisfies both this feature and the existing bar session-count module
      (the bar's snapshot file is unchanged and still parses).
- [x] ~~`services/ai/AgentGraphService.qml` — single-sourced sessions,~~
      per-session nodes/edges, event ring buffer, hardware tier resolution,
      replay archive access. No consumer keeps its own copy.
- [x] ~~Hook plumbing without polling: one long-lived `tail -n 400 -F`~~
      process into a `SplitParser`, not a re-list on a timer. Every record
      is idempotent by `(sessionId, event, toolId, t)`, which is what makes
      log rotation and shell restarts safe rather than duplicating nodes.

### Phase 1 — Static graph render (branch: `feature/agent-graph-render`) — DONE 2026-08-29
- [x] ~~Render a non-live, hardcoded sample graph first — done through a~~
      throwaway `graphprobe.qml` harness (three sessions, a subagent
      branch, a failed call, an ended session), screenshotted and iterated
      on until it drew correctly. `GraphView.sessions` is a plain property
      precisely so a harness can feed it; no sample data ships in the
      product, and the probe was deleted.
- [x] ~~Wire `AgentGraphService` data into the renderer — `GraphView.sessions`~~
      defaults to the live service, and the tab was verified in the running
      shell (tab bar entry, header, tier chip, empty state).
- [x] ~~Prototype both layout candidates and pick one — see Open Decision 2~~
      above. Radial shipped, force-directed deleted rather than left as a
      dead switch.
- [x] ~~Honour the tier contract: `maxNodesPerSession` caps what is drawn per~~
      session, `edgeParticles` sets packet density, `surfaceVisible` is
      bound to the tab's visibility. **`layoutHz` is inert for this
      renderer** — radial has no relaxation loop to tick. The service still
      exposes it for the physics/native paths (Phase 3.5, G3); it is not
      wired into `GraphView` rather than being wired to nothing.
- [x] ~~Settle detection — not applicable in the form the phase anticipated,~~
      and better: radial is settled by construction, so there is no loop to
      stop. Nothing simulates when nothing changes.

Two things worth knowing before Phase 2 touches this:
- `Repeater` delegates must be `Item`s, and `ShapePath` is not one, so a
  `Repeater` of `ShapePath` inside a `Shape` silently draws nothing. Edges
  are grouped by status into three `ShapePath`s fed by `PathMultiline` —
  which is also three geometry nodes for the whole graph instead of one
  per edge.
- Every packet on every edge is driven by one shared `flowClock` with phase
  from the packet index, so N particles cost one running animation, and it
  stops when nothing is in flight.

### Phase 2 — A living graph (branch: `feature/agent-graph-alive`) — DONE 2026-08-29
Agent state drives motion, and motion is the primary status channel.
- [x] ~~Packets/particles travelling along edges while a call is in flight.~~
      Density from `AgentGraphService.edgeParticles`, all packets on one
      shared clock. Speed carries how long the call has been running — a
      fresh call streams fast, one grinding for 20 s slows to a crawl.
      Integer speed multipliers only, since a fractional one jumps at every
      wrap of the shared clock. Opacity ramps toward the child end, which is
      the direction cue.
- [x] ~~Per-state visual behaviour, one vocabulary. Running breathes (the~~
      shared `BioluminescentGlow`, not a graph-specific highlight) and
      flows; waiting holds a steady glow without breathing; errored keeps a
      persistent glow in the error colour; ended drops to half opacity and
      lingers until the service prunes it. Because the glow is the shared
      component, it honours the global `depthEffects` tier automatically —
      and state stays legible without it (pill fill, scale, edge weight).
- [x] ~~Hover a node → tooltip with tool/session name, status, duration, and~~
      subagent type; sessions also show their cwd and call count. One
      tooltip for the whole view, reusing the tab/popout chrome rather than
      a new card style. Duration ticks live for running calls off a 1 Hz
      timer that only runs while something is in flight.
- [x] ~~Click a node → selects it (pins the tooltip, deepens the glow). A~~
      session node additionally tries to focus the terminal running it,
      matched best-effort by the session's `cwd` leaf against window titles
      via the existing `WindowList.focus`. `cwd` was added to the wire
      format for this — it costs nothing and the bar can ignore it.
- [x] ~~Settings → Personalization: `agentGraphQuality` picker~~
      (Auto/Lite/Standard/Full) and a graph accent override, both using the
      existing `SettingsPresetRow`/`ColorPickerField` conventions. Accent
      follows the theme when left empty, exactly like the per-icon overrides.

Known gap: click-to-focus is a title match, not a real session→window link.
Claude Code gives hooks no window or PID, so nothing better is available
without the terminal cooperating. It fails silently when there is no match,
which is the right failure for a convenience action.

### Phase 2.5 — Zoom & navigation (branch: `feature/agent-graph-zoom`) — DONE 2026-08-29
- [x] ~~Pan/zoom: wheel and pinch zoom toward the pointer (not the centre),~~
      drag to pan, clamped 0.3x-4x. Zoom buttons in the corner for
      discoverability, on the shared `StyledRect`/`StateLayer` chrome.
- [x] ~~Zoom-dependent detail: tool labels drop below 0.72x, everything but~~
      the pill drops below 0.42x. This is a legibility rule before a cost
      one - fixed-size pills at ten sessions become text soup long before
      they become a frame-budget problem.
- [x] ~~Zoom-to-fit, and clicking a session root frames it (and still tries~~
      to focus its terminal).
- [x] ~~Offscreen nodes and their edge particles stop rendering entirely -~~
      `_onScreen` culls against the current zoom/pan with a small margin.
      Layout itself is one-pass, so there is nothing further to skip.

Not verified: wheel, pinch and drag have never been driven by a real
pointer - the handlers are declarative and standard, but this branch's
zoom testing was all programmatic.

### Phase 3 — Execution replay (branch: `feature/agent-graph-replay`) — DONE 2026-08-29
**The centerpiece.** Every execution already produces a durable event stream
(`agent-runs/<session_id>.jsonl`, written by the hook, read by
`AgentGraphService.loadRun()` — both shipped in Phase 0).
- [x] ~~Run picker: list archived runs (`AgentGraphService.runs`), pick one,
      load it, leave live mode without losing it.~~ Run chips in `ReplayBar`;
      the Replay toggle switches the tab's source and switching back leaves
      live state untouched, because live ingestion never stopped.
- [x] ~~Transport: play/pause, scrub, speed (1x/2x/8x/max), step-by-event.~~
      Plus the idle-gap compression that makes it watchable: wall-clock gaps
      longer than 1.2 s collapse to 1.2 s, so a run with a four-minute think
      in it plays as 33 s instead of 4.5 minutes. Verified on a synthetic
      44-event run.
- [x] ~~The replayed graph is the *same* renderer as live — same nodes, same
      particles, same states. Replay is a different clock, not a different
      view.~~ Enforced structurally: the reducer that folds events into
      sessions (`AgentGraphService.applyTo`) is shared, and the tab only
      swaps where `GraphView.sessions` comes from. Folding forward is
      incremental; only a backwards seek refolds, which keeps playback off
      an O(n^2) path.
- [x] ~~Timeline strip under the graph: one lane per session/subagent, tool
      calls as blocks, errors marked. Clicking a block seeks to it.~~ Laid
      out on the compressed clock, not wall time, for the same reason as
      the transport.
- [x] ~~Export a run (JSONL as-is, plus a shareable summary).~~ JSONL as-is
      to `~/agent-run-<id>.jsonl` with a toast. **The "shareable summary"
      half was not built** — deliberately deferred rather than half-done;
      a summary format is a design question, not a plumbing one.

### Phase 3.5 — Physics/perf pass (branch: `feature/agent-graph-physics`) — SKIPPED 2026-08-29, on measurements
- [x] ~~Only enter this phase if profiling shows JS-side layout dropping
      frames at realistic node counts *on the low tier*.~~ Profiled on the
      low tier (software-rendered QEMU VM, tier resolves to `lite`) against
      a real 55-node session:
      - **Settled graph, 55 nodes, nothing running: 0.00% CPU.** Radial
        settles by construction, so there is no layout loop to profile. The
        phase's premise — a JS layout loop dropping frames — does not exist
        in the shipped design.
      - **One running call, particles and glow animating: ~10% CPU** on that
        same software-rendered VM. That is rendering cost (blurred glow and
        edge particles under llvmpipe/virtio), not layout, and it only
        applies while an agent is actually working.
- [x] ~~Cheap wins before expensive ones: Barnes-Hut and a tighter node
      budget.~~ Not needed — there is no all-pairs loop to approximate. The
      node budget already exists as `maxNodesPerSession`.
- [x] ~~Native rendering and RHI compute are no longer scoped here~~ — they
      are G3 on the GPU rendering track.

If anyone ever does complain about cost, the thing to look at is the
`BioluminescentGlow` blur on running nodes under software rendering, not the
layout.

### Phase 4 — Ship & fold in (branch: `feature/agent-graph-shipit`) — partly done, rest held
- [ ] README: add the graph surface to the Quickshell Shell module table and
      Roadmap section. **Held deliberately, not forgotten.** The README is
      public and nothing here is merged yet; a module-table entry declares
      the feature shipped. PR #25 already carries the agreed teaser-level
      visibility. Do this when the branches merge.
- [ ] Move the "AI-native differentiators" roadmap line to reference this
      feature. Same reason, same trigger — do it with the merge.
- [x] ~~Delete this file~~ — **superseded.** The append-and-strike-through
      rule (see "Doc convention" at the top) replaced this instruction: the
      file stays as the historical log of what was planned, what shipped and
      what changed course.
- [x] ~~Add a condensed permanent summary to `docs/ROADMAP.md` (architecture
      pattern chosen, file locations, known limitations).~~ Done — see
      "Agent graph — shipped architecture" there. It is written to stand on
      its own if this file is ever lost.
- [x] ~~Carry the GPU rendering track (G1/G2/G3) into `docs/ROADMAP.md`.~~
      Done when the track was first recorded.

---

## Frontier backlog — see `docs/FRONTIER.md` (recorded 2026-08-29, not scheduled)

`docs/FRONTIER.md` holds the long-range idea set (gaming telemetry
visualisations, security topology/eBPF work, the runtime event fabric).
**Nothing there is actionable until this file is finished and tested**, and
it is recorded rather than planned. Two structural observations worth
keeping so the connection isn't rediscovered later:

- Its "Existing GPU / Wayland Foundations" three **are** the G1/G2/G3 track
  below, written up independently. Everything else in FRONTIER sits on top
  of that track — the gaming and security visualisations all assume
  GPU-native rendering exists first.
- Its "Aphotic Runtime Event Fabric" is a generalisation of what Phase 0
  already built for one domain: one JSON-line schema, an append-only
  rotating tail, an idempotent reducer, a durable per-run archive and a
  replay clock. If that substrate is ever generalised, the agent pipeline is
  the prototype to generalise **from**, not a special case to work around.

## GPU rendering track (first-class, sequenced — G1 → G2 → G3)

Three features that used to be parked here as "adjacent, someday" are now
the project's deliberate path into native GPU rendering, in dependency
order. Each one is a real feature on its own; together they are a ladder,
and each rung pays for the next one's infrastructure.

**This does not reverse Phase 0's decision — it completes it.** The
declarative renderer ships first because it works now and costs nothing to
install. The native track is where the graph is *going*, not a contingency
if the declarative version disappoints. Nothing on this track starts before
the graph is visible, live and useful in pure QML.

### G1 — Shader-driven telemetry materials (the warm-up)
The lowest-risk introduction to custom GPU rendering: no new process model,
no Wayland protocol work, no C++ required to start.
- Bar segments, popout chrome and graph edges whose fragment shaders take
  live telemetry as uniforms — CPU/GPU utilization, network throughput,
  tokens/sec from an active agent, agent activity level. A shell that
  visually breathes with what the machine is actually doing, rather than
  swapping icon states.
- Start with `ShaderEffect` + `.qsb` (declarative, contributor-only `qsb`
  dependency, no install-time compile). Escalate to a real `QSGMaterial`
  subclass only where a uniform-driven `ShaderEffect` genuinely can't
  express the effect.
- **What it establishes for later rungs:** the shader authoring/compile
  pipeline, committed `.qsb` artifacts, a documented contributor build
  step, and a first honest read on RHI portability across the hardware
  spread (software-rendered VM → RTX 4090).
- **Depends on:** nothing. Can start any time after the graph renders.

### G2 — True window-peek thumbnails (low-level buffer/texture integration)
Aero Peek for Hyprland: live window previews on hover. No Hyprland or
Quickshell shell has shipped this.
- A custom `QQuickItem` consuming `wlr-screencopy` output and presenting it
  as a live-updating `QSGTexture`, bypassing Quickshell's exposed API where
  it has to.
- **The core technical problem is buffer handling, not drawing:** DMA-BUF
  import, format/modifier negotiation, frame synchronization and lifetime,
  and getting a compositor-owned buffer into a Qt texture without a CPU
  round-trip. Budget the investigation there.
- Cost control is part of the feature, not a follow-up: capture only while
  a preview is actually on screen, at a capped rate, one buffer per
  previewed window — the same "nothing renders while nothing is visible"
  rule the graph already follows.
- **What it establishes for later rungs:** the first compiled C++ QML
  module that ships to users (install-time build step or prebuilt binary,
  CONTRIBUTING.md build section, install.sh integration), plus real
  experience owning GPU resources by hand.
- **Depends on:** G1's build/shader pipeline being real, so the compile
  step is an extension of something that already exists rather than a
  first.

### G3 — GPU-native multi-agent execution graph (the destination)
The declarative graph from Phases 1–3, re-rendered natively once the
infrastructure from G1 and G2 exists.
- Custom `QQuickItem` with `updatePaintNode` emitting `QSGGeometryNode`s
  and custom `QSGMaterial`s directly — not `Repeater`/`ListView` of
  `Item`s. Nodes and edges become instanced geometry in GPU buffers rather
  than one QQuickItem per node.
- Layout relaxation moves to `QRhi` compute, which is what lifts the node
  ceiling past the point the Phase 0 benchmark puts the JS loop at.
- Real-time execution visualization at scale: many concurrent sessions,
  thousands of tool-call nodes, particle flow along every live edge without
  a per-particle scene-graph item.
- **Feasibility is already proven, not assumed** — Phase 0 built a
  `QSGGeometryNode`-emitting `QQuickItem` and imported it into Quickshell
  0.3.0. What remains is cost and scope, not "can it work".
- **Depends on:** G1 (shader pipeline) and G2 (shipped compiled module,
  install story, GPU resource ownership). Also depends on the declarative
  graph being finished — G3 replaces a renderer, so there has to be one.
- **Entry condition:** don't start G3 to make the graph faster. Start it
  when the graph is *useful* and something concrete needs a scale the
  declarative renderer can't reach. The Phase 3.5 note stands — the
  expected finding at realistic session counts is that the JS loop holds.

### Tiering applies to the whole track
Every rung inherits the hard rule above: tiers scale how much is simulated
and how often, never how it looks, and a resident Ollama model gets
priority on the GPU over anything decorative.

---

## Opt-in scope: the agentic stack is a TOML choice, not a default (added 2026-08-29)

**Requirement, not yet built.** Aphotic has to serve two users from one
install: someone who wants the full agentic overview (agent graph, live
session tracking, replay, AI chat, local models) and someone who wants a
clean Hyprland daily driver with easy chat and nothing else running in the
background. Today the agent stack is simply present — `install.sh` wires the
Claude Code hooks unconditionally, the usage timer is enabled
unconditionally, and the bar's agent module polls whether or not anyone
wants it.

What this needs — **first pass shipped 2026-08-29, branch
`feature/agentic-opt-in`**. Correction to the framing above: `aphotic.toml`
did **not** need a new table. `[install] layers` already carries an `ai`
layer; the stack was simply never gated on it. Building a parallel
`[agentic]` section would have been the second config system this repo's
conventions forbid.
- [x] ~~`aphotic.toml` grows a feature-enablement table~~ — superseded:
      gated on the existing `[install] layers` `ai` entry instead.
- [x] ~~`install.sh` reads it and respects it, including on re-run: turning a
      feature off after the fact should remove what it added.~~ Both the
      `aphotic-agent-usage` timer and the Claude Code hook wiring now follow
      the `ai` layer, and de-selecting it on a re-run disables the timer and
      calls the new `remove_claude_code_hooks()` — which drops only the
      entries pointing at this repo's own `agent_hook.sh`, leaves every
      other hook the user has, and prunes hook events left empty. Verified
      against a settings.json holding both an Aphotic entry and an unrelated
      one.
- [x] ~~The shell has to degrade honestly with the stack off: the Agent
      Graph tab should not appear at all.~~ `services/InstallProfile.qml` is
      the single source for what the installer enabled; AI Chat and Agent
      Graph are absent from the Command Center tab list when `ai` is off,
      and `AgentGraphService`'s event tail does not start. Verified live:
      with `layers = ["gaming"]` the tab bar shows Dashboard, Performance,
      Workspaces, Wallpapers and nothing else.
- [x] ~~Profiles as presets over the same layer list — "everything", "daily
      driver", and cherry-pick.~~ Added to `prompt_layers` as a shortcut
      over the same list the per-layer questions already build, not a second
      mechanism: 1 = `gaming,dev,ai,exploit`, 2 = none, 3 = answer each
      question (the old behaviour, still the default). The `ai` question now
      also says what enabling it does — it is the only layer that writes
      into a file outside this repo.
- [x] ~~Document the split in `docs/AGENT_TRACKING.md` (which still reads
      as though the hook is always wired).~~ Done — it now opens with the
      opt-in statement.
- [ ] Document the split in README's install section. **Deliberately not
      done unilaterally:** the README is public and Trevin's standing
      instruction is that this work stays teaser-level there for now. The
      text to add is a factual install note (the `ai` layer wires Claude
      Code hooks into `~/.claude/settings.json`), which is arguably a
      consent disclosure rather than a feature announcement — his call which
      it is.
- [x] ~~The bar's own agent module is not gated yet — it still polls
      `pgrep` every 5 s regardless.~~ Now gated: `AgentIndicator` is absent
      (zero implicit size, not merely hidden, so the bar leaves no gap) and
      both `AgentProviders` polling timers stop, so a daily-driver install
      spawns no `pgrep`/`ollama` processes at all.

Design note worth keeping: an absent or unreadable `aphotic.toml` counts as
*enabled*, not disabled. Someone running from a git clone before ever
running `install.sh` should see the shell they cloned, not a silently
stripped one — only an explicit config turns a layer off.

Sequencing note: this is worth doing **before** the agent graph is announced
anywhere, because "installs Claude Code hooks into your settings.json" is a
thing users should opt into, not discover.

## Multi-source ingestion: other agentic tools, per-call drill-down, remote workspaces (recorded 2026-08-29, not scheduled)

**Requirement, not yet scoped in detail — floor only, per Trevin: "doesn't
need to be worked now, it's a large request to bundle."** Recorded here so
the shape isn't lost, not as a phase to start on.

**The ask:** the graph should be able to represent any agentic workflow
running on the machine, not just Claude Code — named explicitly: OpenCode,
Codex, LM Studio, Unsloth, "all the popular local platforms." Plus two
follow-ons: per-node drill-down (inspect a single `Bash`/`Python`/etc. call's
actual input/output from inside the graph, not just its status pill) and
visibility into **remote** agentic workspaces (cloud dev boxes, hosted AI
cloud operations), with local staying simple to configure and remote going
through something secured and durable rather than an ad hoc pipe that breaks
on the next refactor.

**Why this is a floor, not a plan:** the four named tools are not one shape.
Scoping them honestly means splitting them before designing anything:
- **OpenCode, Codex — genuine agentic CLIs**, same shape as Claude Code:
  a session runs, calls tools, produces a call tree. These map onto the
  *existing* wire format (see "Wire format" above) directly — new work is an
  **adapter per tool**, translating whatever each one's own hook/log/event
  surface emits into `{sessionId, event, tool, toolId, t, ...}`, not a
  schema change. `AgentGraphService` and `GraphView` should not need to know
  which CLI produced an event.
- **LM Studio — a model host, not an agent.** It has no tool-call loop of
  its own; it serves inference requests other things call. Treating it like
  a fourth session-producing CLI would be modeling the wrong thing. It likely
  belongs where Ollama already sits — a *provider* the tier logic accounts
  for (`AgentGraphService._gpuContended`), and optionally its own lightweight
  request-level surface, not a node in the same call tree.
- **Unsloth — a fine-tuning framework, not an agentic tool.** No sessions, no
  tool calls; the natural unit is a training run (loss curve, epoch, GPU
  utilization over time). That is a different data shape than
  session/node/edge and does not belong on the same graph without forcing a
  fit. Worth a second surface, not a fourth adapter into this one.
- General principle for "all the popular local platforms": before adding any
  tool, classify it into one of the three buckets above first. The adapter
  work is only worth doing for tools in the first bucket.

**Per-call drill-down:** the wire format already carries `tool`/`toolId`; it
does not currently carry the call's actual input or output. Hooks would need
to capture a bounded preview of both (size-capped — these events already
flow through a rotating log and an idempotent reducer built for small
records) and the UI would need an expanded-node or side-panel view distinct
from the existing hover tooltip. Two open questions to resolve before
building, not after: how much of a `Bash` command's stdout is safe/useful to
retain (secrets in output are a real risk once this is persisted to a
per-run archive), and whether drill-down reads live off the tail or only
against a completed/archived run (replay already solves "look at what
happened after the fact" — live drill-down while a call is still running is
the harder, unsolved half).

**Remote agentic workspaces:** everything shipped so far assumes a trusted
local file (`~/.local/state/aphotic/agent-events.jsonl`, tailed with
`tail -F`) and a hook script invoked in-process. Neither assumption holds
for a remote box. This needs actual transport design, not a bigger tail
command:
- Local stays exactly as it is — file + `tail -F`, zero setup, matches this
  doc's own "compositor-first, zero-polling" bar (see the guiding-principle
  note in `docs/LEDGER.md`'s consolidation entry).
- Remote needs an authenticated, encrypted channel the remote hook pushes
  through — not a raw open port, not credentials in a config file checked
  into anything. A durable queue or a relay this repo already trusts is a
  better starting point than inventing a bespoke protocol.
- The reducer (`AgentGraphService.applyTo`) is already transport-agnostic —
  it folds records, not connections — so a remote source is a new *producer*
  feeding the same `_ingest`/`applyTo` path, not a rewrite of the ingestion
  logic. The hard part is entirely the secure transport, not the data model.
- This is the same "AI execution data" domain `docs/FRONTIER.md`'s Aphotic
  Runtime Event Fabric entry already names as one of the things a
  generalized substrate should cover — if that substrate ever gets built,
  remote agentic sources are a natural first real client of it, not a
  one-off.

## Licensing and attribution (added 2026-08-29)

The repo is GPL-3.0 (`LICENSE`, README's footer). That already covers the
substance of "it should be licensed and tagged when used outside this repo":
GPL-3.0 is copyleft, so a derivative shipping these modules has to stay
GPL-3.0 and keep the notices intact.

Done in the Phase 3 branch:
- [x] ~~SPDX headers on the modules this workstream introduced~~
      (`SPDX-License-Identifier: GPL-3.0-only` +
      `SPDX-FileCopyrightText`) — the agent graph modules, the replay
      controller and bar, `AgentGraphService`, and the hook worker. SPDX is
      what makes a file self-identifying once it has been copied out of the
      repo, which is exactly the "tagged when in use outside of this repo"
      ask.

Open, and **Trevin's call, not an implementation detail**:
- [ ] Sweep SPDX headers across the rest of the tree, or leave them only on
      the novel modules. Partial coverage is defensible (tag what is worth
      tracking) but should be a decision, not an accident.
- [ ] Whether the copyright line should name Trevin specifically rather than
      "Aphotic-Hypr contributors". This affects who can enforce or relicense
      and is not a decision to make on someone's behalf.
- [ ] Whether anything warrants terms beyond GPL-3.0 — e.g. a `NOTICE` file
      requiring visible attribution for the agent graph, or dual-licensing
      the novel modules. Changing or adding license terms is legally
      significant and irreversible in practice once released, so nothing
      here was changed unilaterally.

## Definition of done for this doc's lifecycle

This file stays in the repo, checklist-driven, until Phase 4 is checked off.
Every "continue feature changes" session should leave at least one checkbox
in a different state than it found it, on its own feature branch, with
open decisions it made written into that branch's PR description — never
left as a question back to Trevin unless the decision is genuinely
irreversible (e.g. "add a compiled C++ plugin to the build" qualifies as
irreversible-enough to flag explicitly, everything else doesn't).

ADDITIONAL FEATURES REQUIRE DESIGN FLOW: 

True window-peek thumbnails. Hyprland/Quickshell has no Aero-peek equivalent. Doing it right means a custom QQuickItem binding directly to wlr-screencopy buffers as a live-updating QSGTexture, bypassing anything Quickshell’s API currently exposes — hard, low-level, and nobody in the Hyprland ecosystem has shipped it.
	•	Shader-driven telemetry materials. Custom QSGMaterial fragment shaders on bar segments driven by live uniforms (tokens/sec from an active agent, CPU/GPU load) — a shell that visually breathes with what the machine is actually doing, not just icon-swap states. Lower lift than the graph idea, good warm-up before tackling RHI compute.

addition: create and curate claude skills / universal ai skills that integrate for ollama, claude, codex, etc. unified dev ai workstation with full visibility. prompt suggestions and full on scoping to dive into the "ai" profile if enabled -- unlocks additional features, presets, etc. needs planning and design (latter of the priorities)
