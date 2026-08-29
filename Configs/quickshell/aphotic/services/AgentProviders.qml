pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Presence + usage for the bar's agent indicator/panel, one entry per
// tracked CLI. Two independent data sources feed `stats`: a 5s
// pgrep/`ollama ps` presence poll (this file), and a 15s FileView read of
// the aggregate record `aphotic agent usage-update` writes every 15
// minutes (never parsed here -- this service only reads that file).
Singleton {
    id: root

    readonly property var providers: [
        { id: "claude", label: qsTr("Claude Code"), icon: "smart_toy", processName: "claude", launchCmd: ["claude"] },
        { id: "codex", label: qsTr("Codex"), icon: "terminal", processName: "codex", launchCmd: ["codex"] },
        { id: "ollama", label: qsTr("Ollama"), icon: "dns", processName: null, launchCmd: ["ollama"] }
    ]

    property var stats: providers.map(() => ({
        sessionCount: 0,
        loadedModels: [],
        todayTokens: 0,
        tokensByModel: [],
        availability: "unavailable",
        liveSessions: []
    }))

    readonly property string selected: Settings.agentSelectedProvider
    readonly property int selectedIndex: providers.findIndex(p => p.id === root.selected)

    function cycle(): void {
        const next = (root.selectedIndex + 1) % root.providers.length;
        Settings.agentSelectedProvider = root.providers[next].id;
    }

    // Right-click contract per spec: always launch (no focus-existing
    // fallback) -- Ollama specifically launches `ollama run <model>` for
    // its first loaded model rather than a bare launchCmd, and no-ops if
    // no model is loaded (nothing sensible to launch).
    function launchSelected(): void {
        const provider = root.providers[root.selectedIndex];
        if (!provider)
            return;
        if (provider.id === "ollama") {
            const loaded = root.stats[root.selectedIndex]?.loadedModels ?? [];
            if (loaded.length === 0)
                return;
            Quickshell.execDetached(["kitty", "-e", "ollama", "run", loaded[0]]);
            return;
        }
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

    Process {
        id: claudePgrep
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim(), 10);
                root._setStat(root._findIndex("claude"), { sessionCount: isNaN(n) ? 0 : n });
            }
        }
    }

    Process {
        id: codexPgrep
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim(), 10);
                root._setStat(root._findIndex("codex"), { sessionCount: isNaN(n) ? 0 : n });
            }
        }
    }

    Process {
        id: ollamaPs
        command: ["ollama", "ps"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").slice(1).filter(l => l.length > 0);
                const models = lines.map(l => l.trim().split(/\s+/)[0]).filter(Boolean);
                root._setStat(root._findIndex("ollama"), { loadedModels: models });
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            claudePgrep.exec(["pgrep", "-x", "-c", "claude"]);
            codexPgrep.exec(["pgrep", "-x", "-c", "codex"]);
            ollamaPs.running = true;
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
                for (const id of ["claude", "codex", "ollama"]) {
                    const p = data.providers?.[id];
                    if (!p)
                        continue;
                    root._setStat(root._findIndex(id), {
                        availability: p.availability ?? "unavailable",
                        todayTokens: p.todayTokens ?? 0,
                        tokensByModel: p.tokensByModel ?? []
                    });
                }
            } catch (e) {
                // Missing/invalid record -- leave last-known stats as-is
                // rather than resetting to zero (spec: never show a false
                // zero for a real outage).
            }
        }
    }

    // Live per-Claude-session activity from Configs/.local/lib/aphotic/
    // agent_hook.sh -- one JSON file per running session
    // ({event, tool, updatedAt}, see that script's own header comment),
    // deleted on Stop. Used to only `ls` the directory and keep the
    // filenames -- real work on every Claude Code tool call
    // (agent_hook.sh writes a file on every PreToolUse/PostToolUse/
    // Notification) for zero effect, since nothing ever read a session
    // file's actual content. Now reads each file's content in the same
    // pass (one combined `for f in .../*.json; do ...; done` shell
    // command rather than N separate reads, matching this file's own
    // "minimize process spawns" convention elsewhere) -- one tab-
    // separated "id<TAB>json" line per session, parsed below. No FileView
    // folder-watch API exists for "list of files in a directory that
    // changes", so this still re-lists on the same 5s cadence as
    // presence polling above rather than reacting to individual file
    // writes.
    Process {
        id: sessionLister
        stdout: StdioCollector {
            onStreamFinished: {
                const sessions = text.split("\n").filter(l => l.length > 0).map(line => {
                    const tab = line.indexOf("\t");
                    if (tab === -1)
                        return null;
                    const id = line.slice(0, tab);
                    try {
                        const data = JSON.parse(line.slice(tab + 1));
                        return {
                            id: id,
                            event: data.event ?? "",
                            tool: data.tool ?? "",
                            updatedAt: data.updatedAt ?? ""
                        };
                    } catch (e) {
                        return null;
                    }
                }).filter(s => s !== null);
                root._setStat(root._findIndex("claude"), { liveSessions: sessions });
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const dir = `${Quickshell.env("HOME")}/.local/state/aphotic/agent-sessions`;
            sessionLister.exec(["sh", "-c", `for f in "${dir}"/*.json; do [ -f "$f" ] && printf '%s\\t%s\\n' "$(basename "$f" .json)" "$(cat "$f")"; done 2>/dev/null`]);
        }
    }
}
