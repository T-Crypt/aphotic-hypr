# Agent Graph

A live, interactive graph of concurrent Claude Code sessions in the
Command Center's dashboard, replacing a flat session list. Each session
is a root node; its tool calls and subagent calls fan out from it as a
call tree, coloured and animated by live status. A finished run can also
be replayed through the same renderer from its own archive.

## Architecture

One event pipeline feeds both the bar's existing agent status and the
graph, so there is exactly one source of truth for session/node/edge
state:

```
agent_hook.py (invoked per Claude Code hook event)
  -> Configs/.local/lib/aphotic/agent_hook.sh (thin exec wrapper)
  -> ~/.local/state/aphotic/agent-events.jsonl   (rotating live log)
  -> AgentGraphService.qml (tail -F via SplitParser, one line = one record)
  -> a shared reducer (AgentGraphService.applyTo) folds records into
     session/node state
  -> GraphLayout.qml turns that state into positions
  -> GraphView.qml renders it
```

The hook also writes a byte-compatible snapshot for the existing bar
consumer (`AgentProviders`, untouched) and a durable per-run archive
under `~/.local/state/aphotic/agent-runs/*.jsonl` that execution replay
reads independently of the live tail.

Every record is idempotent by `(sessionId, event, toolId, t)` because
`tail -F` re-reads from the top on log rotation and startup replays the
tail on purpose — records are not guaranteed to arrive exactly once.

Replay (`GraphReplay.qml`) is a different clock over the same reducer,
not a second implementation of session state: `AgentGraphService.applyTo`
is shared between live ingestion and replay, and swapping `GraphView`
between live and replay mode only changes where its `sessions` property
is sourced from. Wall-clock gaps longer than 1.2s are compressed to 1.2s
during replay so a run with a multi-minute idle gap in it stays watchable
instead of playing back as a mostly-still image.

## Hardware tiering

The same shell runs on a software-rendered dev VM and on a discrete-GPU
workstation, so the graph resolves a hardware tier (`lite` / `standard`
/ `full`) from the detected GPU name (`AgentGraphService._detectedTier`,
via `SystemUsage.gpuName`) unless the user pins one in Settings. Tiers
scale *how much* is simulated — node budget (`maxNodesPerSession`), tick
rate (`layoutHz`), retained event count (`maxEvents`), and edge-particle
density (`edgeParticles`) — never how it looks: every tier renders the
same visual language, and edge particles are thinned by tier but never
switched off entirely, because motion on a running edge is the signal
that the graph is alive rather than a diagram.

The tier demotes one step further while Ollama holds a model resident
(`_gpuContended`, from `AgentProviders.ollamaLoadedModels`) — the graph
should not compete for VRAM with the model it exists to monitor.

## Rendering approach — Open Decision 1: resolved

Two rendering paths were spiked before Phase 0 shipped, and picked on
measurement rather than by argument:

- **A compiled C++ scene-graph plugin** (hand-written `QSGGeometryNode`/
  `QSGMaterial` code, imported into Quickshell via `QML_IMPORT_PATH`).
  Builds cleanly against system Qt 6.11 and stays available as a later
  escalation, but nothing in the current codebase uses it.
- **A declarative path inside Quickshell's own QML engine**, using
  `QtQuick.Shapes` (`Shape` + `ShapePath` + `PathMultiline`, with
  `preferredRendererType: Shape.CurveRenderer` for edges).

The declarative path won: JS radial layout costs 0.40/1.58/3.54/9.04/
36.7 ms per frame at 50/100/150/300/600 nodes, measured on the slowest
target (a software-rendered VM), putting the realistic 150–300 node
ceiling at 21–54% of a 16.67 ms frame budget on the worst hardware this
runs on. **This is the path that shipped in Phases 0–3.**

### On calling this "QSG/RHI"

`Shape.CurveRenderer` *is* RHI-backed under Qt 6's hood, and edges do
render as GPU geometry. But that's Qt Quick Shapes' own renderer doing
its own thing — nothing in this codebase hand-emits
`QSGGeometryNode`/`QSGMaterial`, and no C++ scene-graph plugin is
compiled into the shell. The accurate description is **"RHI-backed
rendering via Qt Quick Shapes"**, not "custom QSG/RHI implementation" —
the latter claims hand-written scene-graph code that was spiked, shelved,
and never shipped. Commit messages, this document, and the README must
keep that distinction.

If a future phase *does* add the hand-written `QSGGeometryNode`/
`QSGMaterial` C++ plugin from the Phase 0 spike, that is the point at
which "QSG/RHI implementation" becomes an accurate claim about this
feature — and it should be flagged loudly as a new architectural
decision when it happens, not blurred with what's already shipped.

## Shipped phases

- **Phase 0 — one event pipeline, tiered by hardware.** The data layer:
  hook rewrite (`agent_hook.py`, one process per event instead of three
  Python spawns plus `date`), the rendering-approach spike above, hardware
  tiering, and the shared idempotent reducer. Two hook-lifecycle bugs
  fixed here: `Stop` fires at the end of every assistant turn (not session
  end), so `SessionEnd` retires sessions and `Stop` only marks idle, with
  a 12h staleness sweep for installs still on the old four-event set.
  Subagent parentage is a documented heuristic, not a guarantee: Claude
  Code hooks give a subagent's tool calls `agent_id` and the *parent*
  session's `session_id`, nothing naming the `Agent`/`Task` call that
  spawned them, so the first call seen for an `agent_id` binds to the
  most recently running `Agent`/`Task` node in that session
  (`AgentGraphService._parentFor`).
- **Phase 1 — render the graph as a Command Center tab.** Layout settled
  by building both candidates: force-directed never stabilized (still
  relaxing after 15s at 15 nodes, a 60Hz loop that never stops, every
  placed node drifting when a new one arrives) despite being cheap
  per-frame, so the failure was behavioural, not a performance one.
  Radial settles by construction, costs nothing at rest, and reads as the
  call tree the data already is — the force-directed path was deleted
  rather than kept as a dead switch (`GraphLayout.qml`). One QML trap hit
  and worth not rediscovering: `Repeater` delegates must be `Item`s and
  `ShapePath` is not one, so a `Repeater` of `ShapePath` inside a `Shape`
  silently draws nothing; edges are grouped by status into three shared
  `ShapePath`s fed by `PathMultiline` instead (three geometry draws for
  the whole graph, not one per edge).
- **Phase 2 — state drives motion ("alive").** Running breathes and
  flows (via the shared `BioluminescentGlow`, not a graph-specific
  highlight), waiting holds a steady glow, errored stays marked in the
  error colour, ended drops to half opacity and lingers. Packet speed
  encodes call age (integer multipliers on one shared clock only — a
  fractional multiplier would visibly jump at every clock wrap). One
  tooltip for the whole view reuses existing tab/popout chrome. Click
  selects a node and, for a session root, best-effort focuses the
  terminal running it by matching window title against the session's
  `cwd` leaf — Claude Code hooks expose no window handle or PID, so this
  fails silently when nothing matches.
- **Phase 2.5 — pan, zoom, and detail that thins out.** Viewport/canvas
  split so layout solves into the viewport's own size and zoom/pan is
  purely a transform on top; nothing in `GraphLayout` knows about zoom.
  Wheel and pinch zoom toward the pointer, clamped 0.3x–4x. Detail thins
  as the graph shrinks — tool labels drop below 0.72x zoom, everything
  but the pill below 0.42x — as a legibility rule before it's a cost one;
  offscreen nodes and their particles stop rendering, which is the cost
  half.
- **Phase 3 — execution replay.** A finished run replays through the
  same `GraphView`/reducer as live data, with a transport, a scrubbable
  timeline (`ReplayBar.qml`), and JSONL export. Folding forward through
  events is incremental; only a backward seek refolds from the start
  (the naive always-refold approach is quadratic over a long run).
  Deliberately not built: a shareable run-summary format — that's a
  design question, not plumbing, and half-doing it would be worse than
  leaving it out.

## Known gaps

- Subagent parentage (Phase 0) and terminal focus-on-click (Phase 2) are
  both best-effort heuristics against data Claude Code's hooks don't
  fully provide — see above. Neither has been verified against a real,
  concurrent multi-agent session on real hardware; all rounds so far
  were verified against synthetic or single-machine test data.
- Run export writes the raw JSONL archive; there is no shareable summary
  format yet (see Phase 3).
