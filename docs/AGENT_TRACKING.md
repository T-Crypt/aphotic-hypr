# Agent Tracking

The bar's agent module (`AgentIndicator.qml` bar icon, `AgentPopout.qml`
hover panel, backed by `services/AgentProviders.qml`) tracks three CLI
providers — Claude Code, Codex, Ollama — through three independent
mechanisms. This doc is the contract for all three, so a change to one
doesn't silently break what another call site assumes.

## 1. Presence polling (all three providers, always on)

`AgentProviders.qml` polls every 5s:
- `pgrep -x -c claude` / `pgrep -x -c codex` → `sessionCount`
- `ollama ps` → `loadedModels`

No setup required — this is what drives the bar icon's fill state and
badge count even on a machine with no hooks or timers configured.

## 2. Usage tracking (Claude + Codex, needs the systemd timer)

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
    "ollama": {"availability": "unavailable", "todayTokens": 0, "tokensByModel": []}
  }
}
```

`AgentProviders.qml` `FileView`-watches this file and never resets a
provider to zero on a missing/invalid record — a real outage should
never show as a false zero.

`Configs/systemd/user/aphotic-agent-usage.timer` runs the update every
15 minutes; `install.sh` enables it unconditionally during the config-copy
stage. `ollama` is in the schema but has no transcript source wired
(Ollama doesn't write one) — always reports `unavailable`, by design, not
a bug.

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

## 3. Live per-session state (Claude Code only, needs the hook wired)

`Configs/.local/lib/aphotic/agent_hook.sh` is a Claude Code hook script:
invoked on `PreToolUse`/`PostToolUse`/`Notification` with the event JSON
piped to stdin, it writes
`~/.local/state/aphotic/agent-sessions/<session_id>.json`:

```json
{"event": "PostToolUse", "tool": "Bash", "updatedAt": "2026-08-25T12:00:00Z"}
```

On `Stop` it deletes that session's file. Never fails the hook (all
steps best-effort, `exit 0` unconditionally) since a slow/failing hook
blocks the calling session's own tool execution.

**Wiring**: `install.sh` calls `lib/install/claude_hooks.sh`'s
`configure_claude_code_hooks()` during the config-copy stage, which
merges (via `jq`, not a template overwrite) `PreToolUse`/`PostToolUse`/
`Notification`/`Stop` entries pointing at this repo's own
`Configs/.local/lib/aphotic/agent_hook.sh` into
`~/.claude/settings.json` — preserving any hooks you already have
configured for other tools, and safe to re-run (replaces only the entry
it previously added, never duplicates). If `jq` is missing or the merge
fails, install.sh warns and continues rather than blocking the install;
wire it by hand by merging the same shape `lib/install/claude_hooks.sh`
produces.

**Known gap — the payload this writes isn't actually read yet.**
`AgentProviders.qml`'s `sessionLister` re-lists
`~/.local/state/aphotic/agent-sessions/` every 5s and populates
`stats[].liveSessions` with the *session-id filenames only* — it never
opens the files, so the `event`/`tool`/`updatedAt` content above is
inert. Neither `AgentIndicator.qml` nor `AgentPopout.qml` reads
`liveSessions` at all today; the bar icon's fill/badge state comes
entirely from `sessionCount` (presence polling, §1). Real "thinking /
editing / waiting" per-session status — the actual ask behind building
this hook in the first place — needs `sessionLister` to read each file's
`event`/`tool` (not just list filenames) and `AgentPopout.qml` to render
per-session rows from it. That's the concrete next step for this
feature, not a hook/install problem.

## Extending to another provider

Codex has no equivalent hook mechanism today, so it's presence-only
(§1) and covered by usage tracking (§2) but can't get live per-session
state (§3) until Codex ships something equivalent to Claude Code's hook
system. If it does, mirror `agent_hook.sh`'s contract (one JSON file per
live session under `agent-sessions/`, `{event, tool, updatedAt}`,
deleted on session end) rather than inventing a second shape —
`AgentProviders.qml`'s `sessionLister` is provider-agnostic by directory
convention already, it just isn't reading the content yet (see above).
