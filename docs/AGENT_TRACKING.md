# Agent Tracking

**All of this is opt-in.** Everything below ships only when the installer's
`ai` layer is selected (`[install] layers` in `aphotic.toml`). With it off,
`install.sh` does not wire the Claude Code hooks and does not enable the
usage timer — and if a previous run enabled them, re-running with the layer
de-selected removes the hook entries and disables the timer. The shell
follows the same signal through `services/InstallProfile.qml`: the bar's
agent indicator, the AI Chat and Agent Graph tabs, and the graph's event
tail are all absent rather than idle. An absent or unreadable
`aphotic.toml` counts as enabled, so a git clone that has never run
`install.sh` still gets the full shell.

The bar's agent module (`AgentIndicator.qml` bar icon, `AgentPopout.qml`
hover panel, backed by `services/AgentProviders.qml`) tracks **harnesses**
only — CLIs that run a session and execute tool calls: Claude Code,
Codex, OpenCode — through three independent mechanisms. This doc is the
contract for all three, so a change to one doesn't silently break what
another call site assumes.

Ollama is a **provider** (inference-only, no tool-execution loop of its
own), not a harness, and deliberately has no tab here — a bare Ollama
process has no session/command shape to show. `services/ai/
AgentRoles.qml` is the single source of the harness/provider
classification; see it and Agent Graph's model-string parsing for how a
provider shows up instead, as an annotation on whichever harness is
using it as a backend. `AgentProviders.qml` still tracks Ollama's
loaded-model state internally (`ollamaLoadedModels`), but only as a
GPU-contention signal for `AgentGraphService`'s render-tier detection —
never as bar-popout state.

## 1. Presence (all harnesses, always on)

`AgentProviders.qml` derives `sessionCount` from whichever of two sources
is authoritative for a given harness:

- **Hook wired (the normal case now that all three harnesses have one,
  §3):** the event tail below drives it in real time, zero polling.
- **No hook configured:** a `pgrep -x -c claude` / `codex` / `opencode`
  reconcile fills in the count instead, on a 60s timer — slow because
  it's a fallback, not the primary signal (`AGF-07`, fixed 2026-08-30:
  this used to be the *only* source, polled every 5s).

No setup required either way — this is what drives the bar icon's fill
state and badge count even on a machine with no hooks or timers
configured.

## 2. Usage tracking (Claude + Codex, needs the systemd timer; OpenCode presence-only)

`aphotic agent usage-update` (`commands/cmd_agent.sh` →
`agent_usage.py`) reads only aggregate token counts from local
transcripts — never prompts, responses, or credentials — and writes
`~/.local/state/aphotic/agent-usage.json`:

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-08-25T12:00:00+00:00",
  "providers": {
    "claude": {"availability": "available", "todayTokens": 425, "tokensByModel": [{"model": "claude-sonnet-5", "tokens": 425}]},
    "codex": {"availability": "unavailable", "todayTokens": 0, "tokensByModel": []},
    "opencode": {"availability": "unavailable", "todayTokens": 0, "tokensByModel": []}
  }
}
```

`AgentProviders.qml` `FileView`-watches this file and never resets a
provider to zero on a missing/invalid record — a real outage should
never show as a false zero.

`Configs/systemd/user/aphotic-agent-usage.timer` runs the update every
15 minutes; `install.sh` enables it unconditionally during the config-copy
stage. `opencode` is in the schema but has no transcript source wired
(no known session-log convention for it yet) — always reports
`unavailable`, by design, not a bug, same as `ollama` did before it was
dropped from this schema entirely (§ above).

**Known limitation**: `agent_usage.py`'s `main()` picks the *first* match
of `~/.claude/projects/*/*.jsonl` / `~/.codex/sessions/*.jsonl` — on a
machine with more than one active project, only one project's transcript
gets summed, not "today's tokens across all projects." Worth fixing by
summing every transcript modified today instead of taking the first
glob hit.

The `"unsupported"` availability value `AgentPopout.qml` renders a message
for is currently dead code — `agent_usage.py` never emits it. Either wire
a real "this CLI version doesn't expose usage data" detection into
`agent_usage.py`, or drop the branch.

## 3. Live per-session state + event stream (Claude Code + Codex, needs the hook wired)

`Configs/.local/lib/aphotic/agent_hook.sh` is a thin `exec` wrapper around
`agent_hook.py`, which does all the work in **one** python process per
event (the old script spawned three `python3` calls plus `date` per firing
— measured 70 ms → 23 ms per hook on a dev VM). It must never fail the
hook: a slow or failing hook blocks the calling session's own tool
execution, so every step is best-effort and the exit status is always 0.

Claude Code invokes it on `SessionStart`, `PreToolUse`, `PostToolUse`,
`PostToolUseFailure`, `Notification`, `Stop`, `SubagentStop` and
`SessionEnd`. It writes three things, all from **one** schema — there is no
second event format anywhere in this project:

**a. The live event stream** — `~/.local/state/aphotic/agent-events.jsonl`,
one JSON object per line, rotating (512 KB → last 1000 lines):

```json
{"v":1,"sessionId":"...","event":"pre_tool_use","status":"running","timestamp":"2026-08-29T16:57:04Z","t":1788022637252,"tool":"Bash","toolId":"toolu_01","agentId":"ag_9","agentType":"Explore","durationMs":42}
```

`event` ∈ `session_start | pre_tool_use | post_tool_use |
post_tool_use_failure | notification | stop | subagent_stop | session_end`.
`t` is epoch ms — the ISO `timestamp` is second-resolution and several tool
calls routinely land in one second, so anything ordering events uses `t`.
`toolId` is Claude Code's own `tool_use_id`, so a `pre_tool_use` pairs with
its `post_tool_use` by id rather than by guesswork. Subagent tool calls
carry the **parent's** `sessionId` plus `agentId`/`agentType`.

**b. The per-session snapshot** — `agent-sessions/<session_id>.json`,
shape `{event, tool, updatedAt, harness}`, a projection of the latest
event rather than a separate schema. `AgentProviders.qml` no longer
reads this (§1/consumers below — it tails (a) directly since `AGF-08`);
kept for `tests/test_agent_hook.sh` / `test_codex_hook.sh` and any
future consumer that wants current per-session state without replaying
the log.

**c. The run archive** — `agent-runs/<session_id>.jsonl`, capped at 25 runs
× 2 MB. The live stream is a rotating tail by design, so replaying a
finished run reads this instead.

**Session retirement changed.** `Stop` fires at the end of every assistant
turn, not at the end of a session — the previous hook deleted the session
file on `Stop`, retiring sessions that were still alive. Now `Stop` marks
the session idle and `SessionEnd` deletes it, with a 12 h staleness sweep
covering installs still wired to the old four-event set. Re-run
`install.sh` (or re-merge `lib/install/claude_hooks.sh`'s shape by hand) to
pick up the four new events.

**Consumers.** `AgentProviders.qml` tails (a) directly for the bar
popout's per-session rows (`AGF-08`, fixed 2026-08-30: this used to `ls`
+ `cat` snapshot (b) on a 5s poll instead — (b) still exists on disk and
still has the same shape, just nothing reads it anymore).
`services/ai/AgentGraphService.qml` tails (a) with its own single
long-lived `tail -n 400 -F` piped into a `SplitParser` — no polling —
and reads (c) on demand for replay. Both tails are independent
processes on the same file rather than one shared source, since QML
singletons don't share a `Process`; each keys its own state off the
record's `harness` field. Records are idempotent by
`(sessionId, event, toolId, t)`, which is what makes log rotation and
shell restarts safe instead of duplicating state. Note `AgentProviders`'
per-session `event` values are this log's own normalized names
(`pre_tool_use`, `post_tool_use`, …), not the raw Claude Code hook names
snapshot (b) used to carry.

## OpenCode's hook (§3, live per-session state)

OpenCode ships a real plugin system (`@opencode-ai/plugin`, bundled with
the CLI install at `~/.opencode/node_modules/@opencode-ai/plugin`) with
a generic `event` hook plus `tool.execute.before`/`tool.execute.after`.
`Configs/.local/lib/aphotic/opencode_hook.js` is a named-export plugin
(`AphoticAgentTracking`) auto-discovered from OpenCode's own global
plugin directory (`~/.config/opencode/plugins/*.js`, symlinked there by
`configure_opencode_hook` in `lib/install/opencode_hooks.sh`, same
`ai`-layer opt-in / add-on-select-remove-on-deselect symmetry as Claude
Code's hook) — no `opencode.jsonc` entry needed, unlike npm-published
plugins.

It does **not** reimplement the three-sink write logic -- it translates
OpenCode's own event vocabulary into the exact same stdin JSON shape
`agent_hook.py` already expects from Claude Code, then spawns that same
script per event. Mapping: `session.created` → `SessionStart`,
`tool.execute.before`/`after` → `PreToolUse`/`PostToolUse`,
`session.idle` → `Stop`, `session.deleted` (and the plugin's own
`dispose()`, for whatever's still tracked when the process exits) →
`SessionEnd`. Model info comes from `chat.params`'s `model.providerID`/
`modelID`, not from `session.created` (OpenCode's `Session` type carries
no model field). Tool names get normalized from OpenCode's lowercase
convention (`bash`) to Claude Code's PascalCase (`Bash`) at the plugin
boundary, via a small lookup table + capitalize-first-letter fallback for
anything not in it -- so `agent_hook.py`, the graph's icon/category
lookups, and the bar all stay completely unaware there's more than one
harness feeding them.

Every record (event log line + session snapshot) now carries a
`harness` field (`agent_hook.py`, defaults to `"claude"` when absent --
backward compatible with every event Claude Code's hook already wrote
before this existed). `AgentProviders.qml`'s `sessionLister` groups
session-snapshot reads by that field and routes each harness's
`liveSessions` to its own tab, instead of the old hardcoded
`_findIndex("claude")`. `AgentGraphService` needed zero changes -- it
already keyed everything off `sessionId`, harness-agnostic by
construction, so OpenCode sessions just started appearing in the graph
the moment the plugin began writing events.

**Known gaps, not fixed here:** no `PostToolUseFailure` equivalent --
OpenCode's `tool.execute.after` input carries no error signal in its
type, so every completed tool call reports `status: "completed"` even
if it actually failed. No `Notification` equivalent. Subagent sessions
(OpenCode nests via `Session.parentID`, not an in-session `agentId` the
way Claude Code's Task/Agent tool calls work) render as independent
top-level sessions in the graph, not nested under their parent -- would
need `AgentGraphService._parentFor`'s model extended to understand
`parentID`-linked sessions, a separate change. Token usage tracking
(§2) is untouched -- OpenCode stores sessions in a local sqlite db
(`~/.local/share/opencode/opencode.db`), not the JSONL transcripts
`agent_usage.py` globs for Claude/Codex, so it still reports
`unavailable` until something queries that db instead.

## Codex's hook (§3, live per-session state)

Codex ships a real lifecycle-hook system: user-level `~/.codex/hooks.json`
(still discoverable next to `config.toml`, same event schema for both
forms). Aphotic wires **`~/.codex/hooks.json`** -- Codex's dedicated hooks
file -- so the user's `config.toml` (provider, auth, MCP, sandbox, ...) is
never touched. `configure_codex_hooks`/`remove_codex_hooks` in
`lib/install/codex_hooks.sh` upsert/remove Aphotic's entries with jq, the
exact merge shape `configure_claude_code_hooks` uses on
`~/.claude/settings.json`, with the same `ai`-layer opt-in and
add-on-select / remove-on-deselect symmetry.

`Configs/.local/lib/aphotic/codex_hook.sh` is the adapter: Codex invokes
it on `SessionStart`, `PreToolUse`, `PostToolUse`, `SubagentStop`, `Stop`
and `SessionEnd`, one JSON object on stdin. Codex's wire payload is
already the same contract `agent_hook.py` reads from Claude Code --
`session_id`, `hook_event_name`, `tool_name`, `tool_use_id`, `agent_id`,
`agent_type`, `model`, `cwd` all match field-for-field, and subagent
events carry the parent `session_id` plus `agent_id`/`agent_type` exactly
like Claude's -- so the adapter does **not** reimplement the three-sink
write logic. Translation is deliberately thin (`codex_hook.py`, one
short-lived process like `agent_hook.py`): tag the record
`harness: "codex"`, map SessionEnd's `reason` to `end_reason` (the name
`agent_hook.py` reads), normalize known tool-name aliases (`shell` →
`Bash`, `apply_patch` → `Edit`, `spawn_agent` → `Agent`; MCP and function
names like `mcp__filesystem__read_file`/`update_plan` pass through
untouched rather than being capitalized), then spawn `agent_hook.py` with
the translated JSON on its stdin -- the same spawn-per-event shape the
OpenCode plugin above uses.

Wiring differences from Claude Code's hook, all deliberate:

- **`async` on `PreToolUse`/`PostToolUse`.** Codex executes those two
  events synchronously, so a sync telemetry hook would add latency to
  every tool call. Background hooks can't block/approve/rewrite -- all
  this telemetry ever needed -- and their output still lands in the same
  three sinks. The lifecycle events (`SessionStart`, `SubagentStop`,
  `Stop`, `SessionEnd`) stay synchronous; they're rare.
- **Timeouts.** SessionStart 5s, Pre/PostToolUse 10s (async), SubagentStop
  and Stop 5s, SessionEnd 3s -- Codex itself caps `SessionEnd` at 3
  seconds (its default is 1), so claude's 10s there would be meaningless.
- **Trust.** Non-managed hooks only run once they've been reviewed and
  trusted against their exact command hash. `install.sh` wires the file,
  then the user opens `/hooks` inside Codex once to trust the Aphotic
  entries (`--dangerously-bypass-hook-trust` exists for one-off automation
  that vets hooks out-of-band). This is a Codex requirement, not an
  Aphotic choice, and the installer prints a reminder after wiring.

Mapping: `SessionStart` → `SessionStart`, `PreToolUse`/`PostToolUse` →
same (Codex's `tool_use_id` pairs them by id, unchanged), `SubagentStop` →
`SubagentStop`, `Stop` → `Stop`, `SessionEnd` → `SessionEnd`. Not mapped:
`SubagentStart` (no Claude equivalent in the contract, so a subagent node
first appears on its own events rather than being pre-registered),
`UserPromptSubmit`, `PermissionRequest`, `PreCompact`, `PostCompact` --
all fire all the time and none maps to a `session_start`→`session_end`
state the graph/bar model.

**Known gaps, not fixed here:** no `PostToolUseFailure` -- PostToolUse
Failure and Notification are simply absent from Codex's hook schema, so an
errored tool call reports `status: "completed"` the same way OpenCode's
does. No `Notification` equivalent. `duration_ms` -- the codex adapter is
one short-lived process per event with no in-memory state between a
`PreToolUse` and its `PostToolUse` (unlike the OpenCode plugin's long-lived
process, which keeps a `toolStarts` map), and Codex's payloads don't carry
a duration, so the graph shows no tool durations for Codex runs. Token
usage (§2) is already covered -- `agent_usage.py` globs
`~/.codex/sessions/*.jsonl` today.

## Extending to another harness

If another harness ships no equivalent hook mechanism, it stays
presence-only (§1) and covered by usage tracking (§2) but can't get live
per-session state (§3). When one does, mirror the contract above rather
than inventing a second shape — same event names, same three sinks,
translate at the harness's own adapter boundary (a plugin, a wrapper
script, whatever that harness supports) rather than teaching
`agent_hook.py` a second input shape.
`AgentProviders.qml`'s `sessionLister` and `AgentGraphService` are both
already harness-agnostic by construction (see above), so a third
harness writing the same lines needs no further consumer changes.

Adding a new harness or provider id starts in `services/ai/
AgentRoles.qml` (role + locality), not here — this doc only covers what
happens once a harness is in that table with `role: "harness"`.
