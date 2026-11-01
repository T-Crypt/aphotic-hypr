pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.ai

// Presence and usage for the bar's agent indicator and popout, one entry
// per harness descriptor (Harnesses.qml). A descriptor exists only for a
// harness whose hook plugin is enabled or that a user drop-in describes,
// so the tab list follows what the user opted into, not what happens to
// be running. Three sources feed `stats`: the shared event feed
// (AgentEvents), a slow pgrep reconcile for a harness whose hook has
// never fired, and the usage record `aphotic agent usage-update` writes.
//
// Providers such as Ollama are not entries here: a provider has no
// session to show. Its loaded models are still tracked below as a GPU
// contention signal for AgentGraphService.
Singleton {
    id: root

    readonly property var providers: Harnesses.visible.map(d => ({
            id: d.id,
            label: d.label,
            icon: d.icon,
            processName: d.match,
            launchCmd: d.launch
        }))

    // The ai layer says the machine has the AI pillar installed; a
    // non-empty `providers` says the user opted a harness's hook plugin
    // in. Both, or this service has nothing anyone will look at -- so
    // neither the reconcile timer nor the shared event feed runs.
    readonly property bool active: InstallProfile.aiEnabled && root.providers.length > 0

    property var stats: providers.map(() => ({
        sessionCount: 0,
        todayTokens: 0,
        tokensByModel: [],
        availability: "unavailable"
    }))

    // Ollama's loaded-model state, tracked independently of the harness
    // `providers`/`stats` pair above -- AgentGraphService reads this to
    // demote render tier when the GPU is busy serving a local model.
    // Derived from AiProviders' single background /api/ps poll rather than
    // a second 5s `ollama ps` subprocess of its own: that CLI call ignored
    // AiConfig.ollamaHost, so it only ever reported a *local* Ollama, and
    // it needed the ollama binary in PATH to say anything at all.
    readonly property var ollamaLoadedModels: AiProviders.ollamaRunningModels.map(m => m.name)
    readonly property var llamaSwapLoadedModels: AiProviders.llamaSwapRunningModels.map(m => m.name)

    readonly property string selected: Settings.agentSelectedProvider
    readonly property int selectedIndex: providers.findIndex(p => p.id === root.selected)

    function cycle(): void {
        const next = (root.selectedIndex + 1) % root.providers.length;
        Settings.agentSelectedProvider = root.providers[next].id;
    }

    function launchSelected(): void {
        const provider = root.providers[root.selectedIndex];
        if (!provider || provider.launchCmd.length === 0)
            return;
        Quickshell.execDetached(["kitty", "-e", ...provider.launchCmd]);
    }

    // The same record `stats` is built from, kept ungated. `stats` only
    // ever covers a harness whose hook plugin the user enabled, but the
    // token counts are read out of transcripts on disk and are just as
    // true for a harness that never fired a hook -- so a surface that
    // wants "how much has this provider used today" asks here instead of
    // indexing `stats` and getting a zero for the wrong reason.
    property var _usageById: ({})

    // Transcript scans cover Claude and Codex. A harness the scan cannot
    // read (OpenCode keeps no transcript to scan) reports usage as v2
    // records on the event stream instead, so those are summed here and
    // served by the same shape. In memory only: it rebuilds as sessions
    // emit, and the scan file stays authoritative for whatever it covers.
    property var _streamUsage: ({})
    property string _streamUsageDay: ""

    // todayCost is null until the harness reports a cost: a transcript
    // scan has none, and a missing number is not zero.
    function usageOf(providerId: string): var {
        const usage = root._usageById[providerId];
        const stream = root._streamUsage[providerId];
        const cost = { todayCost: stream?.todayCost ?? null, currency: stream?.currency ?? "" };
        if (!(usage?.availability === "available") && stream?.tokensSeen)
            return Object.assign({
                availability: "available",
                todayTokens: stream.todayTokens,
                tokensByModel: stream.tokensByModel
            }, cost);
        return Object.assign({
            availability: usage?.availability ?? "unavailable",
            todayTokens: usage?.todayTokens ?? 0,
            tokensByModel: usage?.tokensByModel ?? []
        }, cost);
    }

    // One usage record = one step's token delta. Summed the same way the
    // transcript scan sums its transcripts (input plus output, cache
    // excluded) so a harness's number means the same thing whichever
    // source answered.
    function _noteStreamUsage(record: var): void {
        const harness = record.harness || "";
        if (!harness)
            return;
        const today = new Date().toDateString();
        if (today !== root._streamUsageDay) {
            root._streamUsageDay = today;
            root._streamUsage = {};
        }
        const entry = Object.assign({}, root._streamUsage[harness] ?? { todayTokens: 0, tokensByModel: [], tokensSeen: false, todayCost: null, currency: "" });
        // Cost comes only from the stream, so it counts even when a
        // transcript scan answers for the tokens.
        const cost = typeof record.cost === "number" ? record.cost : Number(record.cost?.amount);
        if (cost > 0) {
            entry.todayCost = (entry.todayCost ?? 0) + cost;
            entry.currency = record.cost?.currency ?? entry.currency;
        }
        if (root._usageById[harness]?.availability === "available") {
            root._streamUsage = Object.assign({}, root._streamUsage, { [harness]: entry });
            return;
        }
        entry.tokensSeen = true;
        const delta = (record.inputTokens ?? 0) + (record.outputTokens ?? 0);
        entry.todayTokens += delta;
        if (record.model && delta > 0) {
            const byModel = entry.tokensByModel.slice();
            const at = byModel.findIndex((m) => m.model === record.model);
            if (at === -1)
                byModel.push({ model: record.model, tokens: delta });
            else
                byModel[at] = { model: byModel[at].model, tokens: byModel[at].tokens + delta };
            entry.tokensByModel = byModel;
        }
        root._streamUsage = Object.assign({}, root._streamUsage, { [harness]: entry });
        root._setStat(root._findIndex(harness), {
            availability: "available",
            todayTokens: entry.todayTokens,
            tokensByModel: entry.tokensByModel
        });
    }

    // A `quota` record off the stream: the named windows the harness
    // reported, keyed by harness id next to the file-backed ones. Both
    // writers merge into the same map so a Claude statusLine reload keeps
    // a live Codex session's windows and vice versa; one shared capture
    // age covers both, the same approximation as before stream quotas.
    function _noteStreamQuota(record: var): void {
        const harness = record.harness || "";
        const windows = record.quota;
        if (!harness || !windows || typeof windows !== "object")
            return;
        root._quotaById = Object.assign({}, root._quotaById, {
            [harness]: { windows: windows }
        });
        const at = record.t ? Math.floor(record.t / 1000) : 0;
        if (at > root._quotaCapturedAt)
            root._quotaCapturedAt = at;
    }

    // Quota windows for one provider: `{ fiveHour, sevenDay, spendLimit,
    // context }`, each `{ usedPercent, resetsAt }`, and any of them
    // absent when the harness did not report it. Empty until a session
    // runs -- the numbers only exist while one is live to state them.
    property var _quotaById: ({})
    property int _quotaCapturedAt: 0

    readonly property int quotaCapturedAt: root._quotaCapturedAt

    // Past this, the record describes a window that has probably rolled
    // over since. Claude Code rewrites its status line continuously
    // during a session and not at all between them, so age is the only
    // signal that the numbers went stale.
    readonly property int quotaMaxAgeSeconds: 1200

    function quotaOf(providerId: string): var {
        return root._quotaById[providerId]?.windows ?? ({});
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

    // One record off AgentEvents' shared feed in,
    // `stats[harness]` usage and quota out. Replaces both
    // the old `ls`+`cat` directory poll (AGF-08) and, for any harness
    // that reaches here at least once, the pgrep poll below (AGF-07).
    // Harnesses without a statusLine slot (Codex, OpenCode) report their
    // quota windows as `quota` records on the same feed instead.
    function _ingestSessionRecord(record: var): void {
        const harness = record.harness || "unknown";
        if (record.event === "usage")
            root._noteStreamUsage(record);
        else if (record.event === "quota")
            root._noteStreamQuota(record);

    }

    // A harness's open sessions, from AgentEvents' fold of the same feed.
    function liveSessionsOf(providerId: string): var {
        return AgentEvents.liveSessions.filter(s => s.harness === providerId);
    }

    // A harness with sessions in the event log is counted from them;
    // one whose hook never fired has only the pgrep sample.
    function _hasEvents(providerId: string): bool {
        return AgentEvents.sessionsOf(providerId).length > 0;
    }

    function sessionCountOf(providerId: string): int {
        if (root._hasEvents(providerId))
            return root.liveSessionsOf(providerId).length;
        return root.stats[root._findIndex(providerId)]?.sessionCount ?? 0;
    }

    // "id@updatedAt" keys a process_exit end was already sent for, so the
    // next sample doesn't repeat it, while a session that resumes and goes
    // quiet again can still be ended.
    property var _endSent: ({})
    // A session must also be this quiet before a zero process count ends
    // it. A descriptor whose match never fits its process (a wrapper, a
    // typo) then can't end a session that is still writing events.
    readonly property int orphanQuietMs: 120000

    function _reconcilePgrepCount(providerId: string, n: int): void {
        if (!root._hasEvents(providerId)) {
            root._setStat(root._findIndex(providerId), { sessionCount: isNaN(n) ? 0 : n });
            return;
        }
        // No process left but sessions still open: the harness exited
        // without a session_end (a closed terminal, a kill). Write the end
        // to the log so every reader, replay included, sees it.
        if (n !== 0)
            return;
        const now = Date.now();
        const quiet = root.liveSessionsOf(providerId)
            .filter(s => now - (s.updatedAt ?? 0) >= root.orphanQuietMs && !root._endSent[`${s.id}@${s.updatedAt}`]);
        if (quiet.length === 0)
            return;
        const sent = Object.assign({}, root._endSent);
        for (const s of quiet)
            sent[`${s.id}@${s.updatedAt}`] = true;
        root._endSent = sent;
        const ids = quiet.map(s => s.id);
        // One process for the batch: a backlog can hold many old sessions.
        Quickshell.execDetached(["sh", "-c",
            'h="$1"; shift; for id; do aphotic agent emit session_end --harness "$h" --session "$id" --end-reason process_exit; done',
            "sh", providerId, ...ids]);
    }

    // Process names the reconcile can count. A descriptor with no `match`
    // (Pi runs as a plain node process) relies on its hook events alone.
    readonly property var _pgrepTargets: root.providers.filter(p => p.processName !== "")

    function _pgrepPattern(): string {
        return root._pgrepTargets.map(p => p.processName.replace(/[.^$|()+{}\\]/g, "\\$&")).join("|");
    }

    // `pgrep -l -x` prints "pid name" per match; every target gets a
    // count, zero included, so a closed session clears.
    function _reconcilePgrepOutput(text: string): void {
        const counts = {};
        for (const line of text.split("\n")) {
            const name = line.trim().split(/\s+/)[1];
            if (name)
                counts[name] = (counts[name] ?? 0) + 1;
        }
        for (const p of root._pgrepTargets)
            root._reconcilePgrepCount(p.id, counts[p.processName] ?? 0);
    }

    Process {
        id: harnessPgrep
        stdout: StdioCollector {
            onStreamFinished: root._reconcilePgrepOutput(text)
        }
    }

    // The event feed drives `sessionCount` in real time for any harness
    // with a hook wired. This keeps the no-setup promise for a harness
    // that never fires one, so a minute between samples is enough.
    Timer {
        id: agentReconcile

        interval: 60000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root._pgrepTargets.length > 0)
                harnessPgrep.exec(["pgrep", "-l", "-x", root._pgrepPattern()]);
        }
    }

    ActivityProbe {
        name: "agents.reconcile"
        kind: "process"
        timer: agentReconcile
    }

    // Quota windows from two writers into one map: the harness's own
    // statusLine command (agent_statusline.py, Claude Code's slot) writes
    // this file on its own cadence, and harnesses with no statusLine
    // slot (Codex) report `quota` records on the event feed instead
    // (_noteStreamQuota). Different cadence and different truth: the
    // usage record counts tokens off transcripts, these carry the share
    // of an allowance a live session itself reports.
    FileView {
        id: quotaFile
        path: `${Quickshell.env("HOME")}/.local/state/aphotic/agent-quota.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (data.schemaVersion !== 1)
                    return;
                root._quotaById = Object.assign({}, root._quotaById, data.providers ?? ({}));
                const at = data.capturedAt ?? 0;
                if (at > root._quotaCapturedAt)
                    root._quotaCapturedAt = at;
            } catch (e) {
                // Same rule as the usage record: a torn or missing file
                // leaves the last-known windows alone rather than
                // blanking bars the user was reading a second ago.
            }
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
                root._usageById = data.providers ?? ({});
                for (const p of root.providers) {
                    const usage = data.providers?.[p.id];
                    if (!usage)
                        continue;
                    // A scan that says unavailable would stomp live stream
                    // numbers with zeros every reload; the stream keeps
                    // the stat until the scan has real data.
                    if (root._streamUsage[p.id]?.tokensSeen && usage.availability !== "available")
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

    // Live per-session activity comes off AgentEvents, the single
    // shared reader of `agent-events.jsonl` (services/ai/AgentEvents.qml)
    // -- this file used to run a `tail -F` of its own beside the
    // agent-graph plugin's, two processes on one file. The hold follows
    // the bar's own tab list: no harness tab, nothing to keep fresh, no
    // tail.
    Connections {
        target: AgentEvents

        function onRecord(event): void {
            root._ingestSessionRecord(event);
        }
    }

    onActiveChanged: AgentEvents.hold("bar-agents", root.active)
    Component.onCompleted: AgentEvents.hold("bar-agents", root.active)
}
