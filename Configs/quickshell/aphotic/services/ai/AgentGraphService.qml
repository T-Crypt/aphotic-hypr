pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Single-sourced state for the agent graph surface. Owns the ONE event
// pipeline shared with the bar's agent popout (Configs/.local/lib/aphotic/
// agent_hook.sh writes it, this reads it) -- no consumer keeps its own copy
// of session/node/edge state, and nothing here re-derives what
// AgentProviders already tracks.
Singleton {
    id: root

    readonly property var sessions: root._sessions
    readonly property var events: root._events
    readonly property int liveSessionCount: root._sessions.filter(s => s.status !== "ended").length
    readonly property int nodeCount: root._sessions.reduce((n, s) => n + s.nodes.length, 0)

    // Set true only while a graph surface is actually on screen. The event
    // tail keeps running either way (parsing a line costs nothing); this
    // gates the expensive half -- layout relaxation in the renderer.
    property bool surfaceVisible: false
    readonly property bool shouldSimulate: root.surfaceVisible && root.nodeCount > 0

    // Hardware tiering, resolved once from real signals rather than assumed:
    // the same shell runs on a software-rendered dev VM and on a discrete-GPU
    // workstation. Tiers scale how MUCH is simulated (node budget, tick
    // rate), never how it looks -- every tier renders the same Aphotic visual
    // language. Manual override values are "lite"/"standard"/"full"; "auto"
    // (the default) resolves below.
    readonly property string tier: {
        const requested = Settings.agentGraphQuality;
        if (requested === "lite" || requested === "standard" || requested === "full")
            return requested;
        return root._demote(root._detectedTier, root._gpuContended);
    }

    readonly property int maxNodesPerSession: root.tier === "full" ? 300 : root.tier === "standard" ? 150 : 60
    readonly property int layoutHz: root.tier === "lite" ? 30 : 60
    readonly property int maxEvents: root.tier === "full" ? 2400 : root.tier === "standard" ? 1200 : 600
    // Edge particles are the "this graph is alive" signal, so they are never
    // switched off by tier -- only thinned. A lite machine still sees flow
    // along a working edge, just fewer packets in it.
    readonly property int edgeParticles: root.tier === "full" ? 6 : root.tier === "standard" ? 3 : 1
    readonly property bool anyRunning: root._sessions.some(s => s.status === "running")

    // Ollama holding models resident is VRAM the graph should not compete
    // for -- an AI-native shell that stutters the model it exists to monitor
    // has its priorities backwards. One tier down while models are loaded.
    readonly property bool _gpuContended: AgentProviders.ollamaLoadedModels.length > 0

    readonly property string _detectedTier: {
        const name = SystemUsage.gpuName.toLowerCase();
        if (!name)
            return "standard";
        if (/qemu|virtio|vmware|virtualbox|llvmpipe|softpipe|cirrus|bochs/.test(name))
            return "lite";
        if (/nvidia|geforce|rtx|quadro|radeon|amd\/ati|navi|arc a[0-9]/.test(name))
            return "full";
        return "standard";
    }

    function _demote(tier: string, should: bool): string {
        if (!should)
            return tier;
        return tier === "full" ? "standard" : "lite";
    }

    readonly property var runs: root._runs
    readonly property string replayRunId: root._replayRunId
    readonly property var replayEvents: root._replayEvents
    readonly property int replaySpan: root._replayEvents.length > 1 ? (root._replayEvents[root._replayEvents.length - 1].t ?? 0) - (root._replayEvents[0].t ?? 0) : 0

    property var _sessions: []
    property var _runs: []
    property string _replayRunId: ""
    property var _replayEvents: []
    property var _events: []
    property var _seen: ({})
    property int _seenCount: 0

    readonly property string _stateDir: `${Quickshell.env("HOME")}/.local/state/aphotic`

    function sessionById(id: string): var {
        return root._sessions.find(s => s.id === id) ?? null;
    }

    function _key(record): string {
        return `${record.sessionId}|${record.event}|${record.toolId ?? ""}|${record.t ?? record.timestamp}`;
    }

    function _ingest(line: string): void {
        let record;
        try {
            record = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (!record || !record.sessionId || !record.event)
            return;

        // tail -F re-reads from the top when the hook rotates the log, and
        // startup replays the tail on purpose, so every record has to be
        // idempotent by key rather than assumed to arrive once.
        const key = root._key(record);
        if (root._seen[key])
            return;
        if (root._seenCount > root.maxEvents * 4) {
            root._seen = ({});
            root._seenCount = 0;
        }
        root._seen[key] = true;
        root._seenCount++;

        const events = root._events.slice();
        events.push(record);
        while (events.length > root.maxEvents)
            events.shift();
        root._events = events;

        root._apply(record);
    }

    function _blankSession(record): var {
        return {
            id: record.sessionId,
            status: "idle",
            model: record.model ?? "",
            startedAt: record.t ?? 0,
            updatedAt: record.t ?? 0,
            endedAt: 0,
            nodes: [],
            agentParents: ({})
        };
    }

    function _apply(record): void {
        const sessions = root._sessions.slice();
        let index = sessions.findIndex(s => s.id === record.sessionId);
        if (index === -1) {
            sessions.push(root._blankSession(record));
            index = sessions.length - 1;
        }
        const session = Object.assign({}, sessions[index]);
        session.nodes = session.nodes.slice();
        session.updatedAt = record.t ?? session.updatedAt;

        if (record.event === "session_end") {
            session.status = "ended";
            session.endedAt = record.t ?? 0;
        } else if (record.event === "stop" || record.event === "subagent_stop") {
            session.status = "idle";
        } else if (record.event === "notification") {
            session.status = "waiting";
        } else if (record.event === "pre_tool_use") {
            session.status = "running";
            root._openNode(session, record);
        } else if (record.event === "post_tool_use" || record.event === "post_tool_use_failure") {
            session.status = "running";
            root._closeNode(session, record);
        } else if (record.event === "session_start") {
            session.status = "idle";
            session.model = record.model ?? session.model;
        }

        sessions[index] = session;
        root._sessions = sessions;
    }

    // Claude Code gives no explicit parent for a subagent's tool calls --
    // they carry agent_id and the PARENT session's session_id, nothing that
    // names the Task call that spawned them. So the first tool call seen for
    // an agent_id is bound to the most recent still-running Task node in that
    // session, and every later call from the same agent_id inherits that
    // binding. Documented heuristic, not a claimed guarantee.
    function _parentFor(session, record): string {
        if (!record.agentId)
            return "";
        const bound = session.agentParents[record.agentId];
        if (bound)
            return bound;
        for (let i = session.nodes.length - 1; i >= 0; i--) {
            const node = session.nodes[i];
            if (node.tool === "Agent" || node.tool === "Task") {
                session.agentParents[record.agentId] = node.id;
                return node.id;
            }
        }
        return "";
    }

    function _openNode(session, record): void {
        const id = record.toolId ?? `${record.event}-${record.t}`;
        if (session.nodes.some(n => n.id === id))
            return;
        session.nodes.push({
            id: id,
            tool: record.tool ?? "",
            agentId: record.agentId ?? "",
            agentType: record.agentType ?? "",
            parentId: root._parentFor(session, record),
            status: "running",
            startedAt: record.t ?? 0,
            endedAt: 0,
            durationMs: 0
        });
        while (session.nodes.length > root.maxNodesPerSession) {
            const oldest = session.nodes.findIndex(n => n.status !== "running");
            if (oldest === -1)
                break;
            session.nodes.splice(oldest, 1);
        }
    }

    function _closeNode(session, record): void {
        const id = record.toolId ?? "";
        const index = session.nodes.findIndex(n => n.id === id);
        if (index === -1)
            return;
        const node = Object.assign({}, session.nodes[index]);
        node.status = record.event === "post_tool_use_failure" ? "errored" : "completed";
        node.endedAt = record.t ?? 0;
        node.durationMs = record.durationMs ?? (node.endedAt && node.startedAt ? node.endedAt - node.startedAt : 0);
        session.nodes[index] = node;
    }

    // Replay reads a finished run's own archive (see agent_hook.py), not the
    // live rotating log -- the live log is a tail by design and a run older
    // than a few hundred events would already be gone from it.
    function refreshRuns(): void {
        runLister.running = false;
        runLister.command = ["sh", "-c", `ls -t '${root._stateDir}/agent-runs'/*.jsonl 2>/dev/null | head -n 25`];
        runLister.running = true;
    }

    function loadRun(id: string): void {
        if (!id)
            return;
        root._replayRunId = id;
        root._replayEvents = [];
        runReader.running = false;
        runReader.command = ["cat", `${root._stateDir}/agent-runs/${id}.jsonl`];
        runReader.running = true;
    }

    function clearReplay(): void {
        root._replayRunId = "";
        root._replayEvents = [];
    }

    Process {
        id: runLister
        stdout: StdioCollector {
            onStreamFinished: {
                root._runs = text.split("\n").filter(l => l.length > 0).map(path => ({
                    id: path.slice(path.lastIndexOf("/") + 1).replace(/\.jsonl$/, ""),
                    path: path
                }));
            }
        }
    }

    Process {
        id: runReader
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = [];
                for (const line of text.split("\n")) {
                    if (!line.length)
                        continue;
                    try {
                        parsed.push(JSON.parse(line));
                    } catch (e) {
                        continue;
                    }
                }
                root._replayEvents = parsed;
            }
        }
    }

    Process {
        id: eventTail
        running: true
        command: ["sh", "-c", `mkdir -p '${root._stateDir}' && : >> '${root._stateDir}/agent-events.jsonl' && exec tail -n 400 -F '${root._stateDir}/agent-events.jsonl'`]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root._ingest(data)
        }
    }

    // Ended sessions linger deliberately so a finished run doesn't vanish
    // mid-glance; the renderer fades them out well before this prunes them.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            const cutoff = Date.now() - 60000;
            const kept = root._sessions.filter(s => s.status !== "ended" || s.endedAt > cutoff);
            if (kept.length !== root._sessions.length)
                root._sessions = kept;
        }
    }
}
