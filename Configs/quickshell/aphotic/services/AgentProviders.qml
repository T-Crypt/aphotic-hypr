pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.ai

// Presence + usage for the bar's agent indicator/panel, one entry per
// tracked harness (a CLI that runs a session and executes tool calls --
// see AgentRoles.qml for the harness/provider distinction). Three
// independent data sources feed `stats`: a live tail of the same
// `agent-events.jsonl` stream AgentGraphService reads (real-time
// `sessionCount`/`liveSessions` for any harness whose hook has fired at
// least once -- see `_hasLiveEvents`), a much-slower pgrep reconcile
// that only fills in `sessionCount` for a harness the tail has never
// heard from (no hook configured -- see docs/AGENT_TRACKING.md section
// 1's "no setup required" guarantee), and an inotify-backed FileView
// read of the aggregate record `aphotic agent usage-update` writes
// every 15 minutes (never parsed here -- this service only reads that
// file).
//
// Ollama is deliberately NOT one of these entries: it's a provider, not a
// harness, and a bare Ollama process has no session/command shape to show
// in this popout. Its loaded-model state is still tracked below, but only
// as an internal GPU-contention signal for AgentGraphService, never as a
// Bar tab.
//
// Bar-tab visibility is gated on the harness's own harness-hook plugin
// being installed+enabled (PluginRegistry.isEnabled, manifest v3 -- see
// docs/archive/PLUGIN_SYSTEM.md's "harness-hook capability"), not on live
// process presence -- a deliberate divergence from Agent Graph's
// AgentRoles.hasConfiguredHarness gate (which stays presence-based) and
// from this file's own pre-plugin-architecture behavior, where a running
// harness showed up in the bar with zero setup. Per direct instruction
// (2026-08-30): the bar icon set should reflect what the user has
// explicitly opted into via the plugin system, the same as any other
// plugin-contributed surface (e.g. Agent Graph's Dashboard tab), not
// what merely happens to be running right now.
Singleton {
    id: root

    readonly property var _uiMeta: ({
        "claude": { icon: "smart_toy", processName: "claude", launchCmd: ["claude"], pluginName: "claude-hooks" },
        "codex": { icon: "terminal", processName: "codex", launchCmd: ["codex"], pluginName: "codex-hooks" },
        "opencode": { icon: "terminal", processName: "opencode", launchCmd: ["opencode"], pluginName: "opencode-hooks" }
    })

    // Set of active harness tabs: ids/enablement come from AgentRoles (the
    // single-sourced role schema) AND from whether that harness's own
    // harness-hook plugin is installed+enabled; icon/pgrep-name/launch
    // command/plugin name are Bar-specific UI metadata, not a
    // classification concern. A harness with no _uiMeta entry (e.g.
    // Gemini CLI -- no known package/binary in this repo yet) is skipped
    // rather than shown with dead detection.
    readonly property var providers: AgentRoles.harnesses
        .filter(h => root._uiMeta[h.id] && PluginRegistry.isEnabled(root._uiMeta[h.id].pluginName))
        .map(h => ({
            id: h.id,
            label: h.label,
            icon: root._uiMeta[h.id].icon,
            processName: root._uiMeta[h.id].processName,
            launchCmd: root._uiMeta[h.id].launchCmd
        }))

    property var stats: providers.map(() => ({
        sessionCount: 0,
        todayTokens: 0,
        tokensByModel: [],
        availability: "unavailable",
        liveSessions: []
    }))

    // Ollama's loaded-model state, tracked independently of the harness
    // `providers`/`stats` pair above -- AgentGraphService reads this to
    // demote render tier when the GPU is busy serving a local model.
    property var ollamaLoadedModels: []

    // { harnessId: { sessionId: {id, event, tool, updatedAt} } }, built
    // entirely from the event tail below -- one entry per still-open
    // session, removed on that session's `session_end`.
    property var _liveByHarness: ({})
    // { harnessId: true } once that harness's hook has written at least
    // one event -- gates the pgrep reconcile timer below out of ever
    // overwriting a harness the tail is already authoritative for.
    property var _hasLiveEvents: ({})

    readonly property string selected: Settings.agentSelectedProvider
    readonly property int selectedIndex: providers.findIndex(p => p.id === root.selected)

    function cycle(): void {
        const next = (root.selectedIndex + 1) % root.providers.length;
        Settings.agentSelectedProvider = root.providers[next].id;
    }

    function launchSelected(): void {
        const provider = root.providers[root.selectedIndex];
        if (!provider)
            return;
        Quickshell.execDetached(["kitty", "-e", ...provider.launchCmd]);
    }

    function _findIndex(providerId: string): int {
        return root.providers.findIndex(p => p.id === providerId);
    }

    function _setStat(index: int, patch: var): void {
        if (index < 0)
            return;
        const next = root.stats.slice();
        next[index] = Object.assign({}, next[index], patch);
        root.stats = next;
    }

    // One line of `agent-events.jsonl` (same schema AgentGraphService
    // tails -- see its header) in, `stats[harness].{sessionCount,
    // liveSessions}` out. Replaces both the old `ls`+`cat` directory
    // poll (AGF-08) and, for any harness that reaches here at least
    // once, the pgrep poll below (AGF-07).
    function _ingestSessionEvent(line: string): void {
        let record;
        try {
            record = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (!record || !record.sessionId || !record.event)
            return;

        const harness = record.harness || "claude";
        if (!root._hasLiveEvents[harness])
            root._hasLiveEvents = Object.assign({}, root._hasLiveEvents, { [harness]: true });

        const sessions = Object.assign({}, root._liveByHarness[harness] ?? {});
        if (record.event === "session_end") {
            delete sessions[record.sessionId];
        } else {
            sessions[record.sessionId] = {
                id: record.sessionId,
                event: record.event,
                tool: record.tool ?? "",
                updatedAt: record.timestamp ?? ""
            };
        }
        root._liveByHarness = Object.assign({}, root._liveByHarness, { [harness]: sessions });

        const list = Object.values(sessions);
        root._setStat(root._findIndex(harness), { liveSessions: list, sessionCount: list.length });
    }

    function _reconcilePgrepCount(providerId: string, n: int): void {
        // The event tail is authoritative the moment a harness's hook has
        // fired once -- never let a slow, coarser pgrep sample stomp a
        // real-time count with a stale one.
        if (root._hasLiveEvents[providerId])
            return;
        root._setStat(root._findIndex(providerId), { sessionCount: isNaN(n) ? 0 : n });
    }

    Process {
        id: claudePgrep
        stdout: StdioCollector {
            onStreamFinished: root._reconcilePgrepCount("claude", parseInt(text.trim(), 10))
        }
    }

    Process {
        id: codexPgrep
        stdout: StdioCollector {
            onStreamFinished: root._reconcilePgrepCount("codex", parseInt(text.trim(), 10))
        }
    }

    Process {
        id: opencodePgrep
        stdout: StdioCollector {
            onStreamFinished: root._reconcilePgrepCount("opencode", parseInt(text.trim(), 10))
        }
    }

    Process {
        id: ollamaPs
        command: ["ollama", "ps"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").slice(1).filter(l => l.length > 0);
                root.ollamaLoadedModels = lines.map(l => l.trim().split(/\s+/)[0]).filter(Boolean);
            }
        }
    }

    Timer {
        interval: 5000
        running: InstallProfile.aiEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: ollamaPs.running = true
    }

    // Presence reconcile, not the primary signal (AGF-07): the event
    // tail below drives `sessionCount` in real time for any harness with
    // a hook wired. This only exists to keep section 1 of
    // docs/AGENT_TRACKING.md's "no setup required" promise for a harness
    // that never fires a hook event at all -- correctness there doesn't
    // need 5s freshness, so this fires 12x slower than it used to.
    Timer {
        interval: 60000
        running: InstallProfile.aiEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root._findIndex("claude") !== -1)
                claudePgrep.exec(["pgrep", "-x", "-c", "claude"]);
            if (root._findIndex("codex") !== -1)
                codexPgrep.exec(["pgrep", "-x", "-c", "codex"]);
            if (root._findIndex("opencode") !== -1)
                opencodePgrep.exec(["pgrep", "-x", "-c", "opencode"]);
        }
    }

    FileView {
        id: usageFile
        path: `${Quickshell.env("HOME")}/.local/state/aphotic/agent-usage.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (data.schemaVersion !== 1)
                    return;
                for (const p of root.providers) {
                    const usage = data.providers?.[p.id];
                    if (!usage)
                        continue;
                    root._setStat(root._findIndex(p.id), {
                        availability: usage.availability ?? "unavailable",
                        todayTokens: usage.todayTokens ?? 0,
                        tokensByModel: usage.tokensByModel ?? []
                    });
                }
            } catch (e) {
                // Missing/invalid record -- leave last-known stats as-is
                // rather than resetting to zero (spec: never show a false
                // zero for a real outage).
            }
        }
    }

    // Live per-session activity, replacing what used to be a 5s
    // `ls`-then-`cat` of Configs/.local/lib/aphotic/agent_hook.py's
    // per-session snapshot directory (AGF-08) -- that re-listed the
    // whole directory on a timer for content that changes on every tool
    // call, real work for zero effect since nothing ever reacted faster
    // than the poll anyway. This tails `agent-events.jsonl` instead --
    // the exact same rotating event log AgentGraphService already holds
    // a `tail -F` on (see that file's header for the schema and the
    // idempotency/rotation reasoning) -- so presence updates the instant
    // a hook fires rather than up to 5s later, and there is one thing
    // being watched on disk instead of two. `_ingestSessionEvent` builds
    // `_liveByHarness` incrementally and keys everything off the
    // record's own `harness` field (defaults to "claude" when absent,
    // same as AgentGraphService), so Claude, Codex and OpenCode sessions
    // all route to their own provider's tab with no per-harness branch
    // here.
    Process {
        id: sessionEventTail
        running: InstallProfile.aiEnabled
        command: ["sh", "-c", `mkdir -p '${Quickshell.env("HOME")}/.local/state/aphotic' && : >> '${Quickshell.env("HOME")}/.local/state/aphotic/agent-events.jsonl' && exec tail -n 400 -F '${Quickshell.env("HOME")}/.local/state/aphotic/agent-events.jsonl'`]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root._ingestSessionEvent(data)
        }
    }
}
