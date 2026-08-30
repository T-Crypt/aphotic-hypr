pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.ai

// Presence + usage for the bar's agent indicator/panel, one entry per
// tracked harness (a CLI that runs a session and executes tool calls --
// see AgentRoles.qml for the harness/provider distinction). Two
// independent data sources feed `stats`: a 5s pgrep presence poll (this
// file), and a 15s FileView read of the aggregate record `aphotic agent
// usage-update` writes every 15 minutes (never parsed here -- this
// service only reads that file).
//
// Ollama is deliberately NOT one of these entries: it's a provider, not a
// harness, and a bare Ollama process has no session/command shape to show
// in this popout. Its loaded-model state is still tracked below, but only
// as an internal GPU-contention signal for AgentGraphService, never as a
// Bar tab.
Singleton {
    id: root

    readonly property var _uiMeta: ({
        "claude": { icon: "smart_toy", processName: "claude", launchCmd: ["claude"] },
        "codex": { icon: "terminal", processName: "codex", launchCmd: ["codex"] },
        "opencode": { icon: "terminal", processName: "opencode", launchCmd: ["opencode"] }
    })

    // Set of active harness tabs: ids/enablement come from AgentRoles (the
    // single-sourced role schema); icon/pgrep-name/launch command are Bar-
    // specific UI metadata, not a classification concern. A harness with
    // no _uiMeta entry (e.g. Gemini CLI -- no known package/binary in this
    // repo yet) is skipped rather than shown with dead detection.
    readonly property var providers: AgentRoles.harnesses
        .filter(h => root._uiMeta[h.id])
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
        id: opencodePgrep
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim(), 10);
                root._setStat(root._findIndex("opencode"), { sessionCount: isNaN(n) ? 0 : n });
            }
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
        onTriggered: {
            if (root._findIndex("claude") !== -1)
                claudePgrep.exec(["pgrep", "-x", "-c", "claude"]);
            if (root._findIndex("codex") !== -1)
                codexPgrep.exec(["pgrep", "-x", "-c", "codex"]);
            if (root._findIndex("opencode") !== -1)
                opencodePgrep.exec(["pgrep", "-x", "-c", "opencode"]);
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
    // writes. Claude Code is currently the only harness with a hook
    // system that populates this directory -- Codex/OpenCode stay
    // presence-only (see docs/AGENT_TRACKING.md) until they ship an
    // equivalent.
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
        running: InstallProfile.aiEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const dir = `${Quickshell.env("HOME")}/.local/state/aphotic/agent-sessions`;
            sessionLister.exec(["sh", "-c", `for f in "${dir}"/*.json; do [ -f "$f" ] && printf '%s\\t%s\\n' "$(basename "$f" .json)" "$(cat "$f")"; done 2>/dev/null`]);
        }
    }
}
