// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.ai

Singleton {
    id: root

    readonly property var sessions: root._sessions
    readonly property var events: root._events
    readonly property int liveSessionCount: root._sessions.filter(s => s.status !== "ended").length
    readonly property int nodeCount: root._sessions.reduce((n, s) => n + s.nodes.length, 0)

    property bool surfaceVisible: false
    readonly property bool shouldSimulate: root.surfaceVisible && root.nodeCount > 0

    readonly property string tier: {
        const requested = Settings.agentGraphQuality;
        if (requested === "lite" || requested === "standard" || requested === "full")
            return requested;
        return root._demote(root._detectedTier, root._gpuContended);
    }

    readonly property int maxNodesPerSession: root.tier === "full" ? 300 : root.tier === "standard" ? 150 : 60
    readonly property int layoutHz: root.tier === "lite" ? 30 : 60
    readonly property int maxEvents: root.tier === "full" ? 2400 : root.tier === "standard" ? 1200 : 600
    readonly property int edgeParticles: root.tier === "full" ? 6 : root.tier === "standard" ? 3 : 1
    readonly property int replayStepEvents: root.tier === "full" ? 1 : root.tier === "standard" ? 2 : 6
    readonly property bool anyRunning: root._sessions.some(s => s.status === "running")

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

    function _hueForSession(id: string): int {
        let hash = 0;
        for (let i = 0; i < id.length; i++)
            hash = (hash * 31 + id.charCodeAt(i)) | 0;
        return Math.abs(hash) % 360;
    }

    // Parsed once per session_start (see applyTo below), never per frame --
    // a harness reports whatever backend it's actually using in the same
    // `model` field regardless of whether that's a hosted cloud model or a
    // local one served through a provider like unsloth/Ollama/LM Studio
    // (e.g. "unsloth/Qwen3.8-27B-GGUF:Q4_K_M" vs "claude-opus-4-x"), so
    // this is a string-classification problem, not a second process to
    // detect. Known provider ids from AgentRoles take priority; a cloud/
    // local heuristic on the string shape is the fallback for anything
    // that doesn't name a known provider outright.
    function parseModelInfo(modelString: string): var {
        const raw = modelString ?? "";
        if (!raw)
            return { label: "", provider: "", locality: "", quant: "", raw: "" };

        const lower = raw.toLowerCase();
        let provider = "";
        for (const p of AgentRoles.providers) {
            if (lower.includes(p.id.toLowerCase())) {
                provider = p.id;
                break;
            }
        }

        let locality = provider ? AgentRoles.localityFor(provider) : "";
        if (!locality) {
            if (/\.gguf\b/i.test(raw) || /\bQ\d(?:_\d)?(?:_K)?(?:_[SML])?\b/i.test(raw) || raw.includes("/"))
                locality = "local";
            else if (/^(claude|gpt|o[0-9]|gemini)[-:]/i.test(raw))
                locality = "cloud";
        }

        const quantMatch = raw.match(/\bQ\d(?:_\d)?(?:_K)?(?:_[SML])?\b/i);
        const ggufMatch = raw.match(/[\w.-]+\.gguf\b/i);
        const quant = quantMatch ? quantMatch[0] : (ggufMatch ? ggufMatch[0] : "");

        const label = raw.length > 28 ? `${raw.slice(0, 25)}…` : raw;

        return { label: label, provider: provider, locality: locality, quant: quant, raw: raw };
    }

    function _blankSession(record): var {
        return {
            id: record.sessionId,
            status: "idle",
            model: record.model ?? "",
            modelInfo: root.parseModelInfo(record.model ?? ""),
            cwd: record.cwd ?? "",
            startedAt: record.t ?? 0,
            updatedAt: record.t ?? 0,
            endedAt: 0,
            hue: root._hueForSession(record.sessionId),
            nodes: [],
            agentParents: ({})
        };
    }

    function _apply(record): void {
        root._sessions = root.applyTo(root._sessions, record);
    }

    function applyTo(existing, record): var {
        const sessions = existing.slice();
        let index = sessions.findIndex(s => s.id === record.sessionId);
        if (index === -1) {
            sessions.push(root._blankSession(record));
            index = sessions.length - 1;
        }
        const session = Object.assign({}, sessions[index]);
        session.nodes = session.nodes.slice();
        session.agentParents = Object.assign({}, session.agentParents);
        session.updatedAt = record.t ?? session.updatedAt;
        if (session.status === "ended" && record.event !== "session_end")
            session.endedAt = 0;

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
            session.modelInfo = root.parseModelInfo(session.model);
        }
        if (record.cwd)
            session.cwd = record.cwd;

        sessions[index] = session;
        return sessions;
    }

    function foldEvents(events, upTo: int): var {
        let sessions = [];
        const limit = Math.min(upTo, events.length);
        for (let i = 0; i < limit; i++)
            sessions = root.applyTo(sessions, events[i]);
        return sessions;
    }

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
        if (record.spawnedAgentId && id)
            session.agentParents[record.spawnedAgentId] = id;
        const index = session.nodes.findIndex(n => n.id === id);
        if (index === -1)
            return;
        const node = Object.assign({}, session.nodes[index]);
        node.status = record.event === "post_tool_use_failure" ? "errored" : "completed";
        if (record.agentDescription)
            node.agentDescription = record.agentDescription;
        node.endedAt = record.t ?? 0;
        node.durationMs = record.durationMs ?? (node.endedAt && node.startedAt ? node.endedAt - node.startedAt : 0);
        session.nodes[index] = node;
    }

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
        running: InstallProfile.aiEnabled
        command: ["sh", "-c", `mkdir -p '${root._stateDir}' && : >> '${root._stateDir}/agent-events.jsonl' && exec tail -n 400 -F '${root._stateDir}/agent-events.jsonl'`]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root._ingest(data)
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            const cutoff = Date.now() - 300000;
            const kept = root._sessions.filter(s => s.status !== "ended" || s.endedAt > cutoff || s.updatedAt > s.endedAt);
            if (kept.length !== root._sessions.length)
                root._sessions = kept;
        }
    }
}
