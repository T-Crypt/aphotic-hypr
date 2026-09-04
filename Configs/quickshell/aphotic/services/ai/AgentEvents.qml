// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// The one reader of ~/.local/state/aphotic/agent-events.jsonl. Every
// surface that wants harness session state -- the bar's agent indicator,
// a notch tile, the Agent Graph plugin -- subscribes here instead of
// opening a tail of its own. Before this existed there were two live
// `tail -F` processes on the same file (core AgentProviders and the
// agent-graph plugin, observed as sibling PIDs), and a third was one
// more consumer away.
//
// Deliberately NOT gated on InstallProfile.aiEnabled. A profile layer
// says what the installer put on the machine; it does not say anyone is
// watching. `hold()` does: the tail runs while at least one surface
// holds it and stops when the last one lets go, so a shell nobody has
// opened an agent surface on runs no tail at all, `ai` layer or not.
//
// This reduces sessions to identity, status and freshness only. Tool-call
// topology, node graphs and run replay stay in the Agent Graph plugin,
// folded from the same records -- see docs/PLUGIN_LAYER_MODEL.md on the
// redundancy boundary between the shared feed and a plugin's own model.
Singleton {
    id: root

    signal record(var event)

    readonly property var sessions: root._sessions
    readonly property var liveSessions: root._sessions.filter(s => s.status !== "ended")
    readonly property var waitingSessions: root._sessions.filter(s => s.status === "waiting")
    readonly property bool anyWaiting: root.waitingSessions.length > 0
    readonly property bool anyRunning: root._sessions.some(s => s.status === "running")

    // Most recently updated live session, which is what a one-line
    // readout means by "the" harness. Null on a quiet desktop rather
    // than the last-ended session: a finished run is not activity.
    readonly property var activeSession: {
        const live = root.liveSessions;
        if (live.length === 0)
            return null;
        return live.reduce((newest, s) => s.updatedAt > newest.updatedAt ? s : newest, live[0]);
    }

    readonly property string activeHarness: root.activeSession?.harness ?? ""
    readonly property string phase: root.activeSession?.status ?? "idle"

    readonly property bool tailing: eventTail.running

    // Set-based, not a counter: a surface that is built and destroyed
    // repeatedly (every notch tile is) can re-assert the same hold any
    // number of times without a missed pairing leaking the tail open.
    function hold(owner: string, want: bool): void {
        if (!owner)
            return;
        if (want === Object.prototype.hasOwnProperty.call(root._holders, owner))
            return;
        const next = Object.assign({}, root._holders);
        if (want)
            next[owner] = true;
        else
            delete next[owner];
        root._holders = next;
    }

    function sessionsOf(harness: string): var {
        return root._sessions.filter(s => s.harness === harness);
    }

    readonly property int historyLines: 400
    readonly property string _stateDir: `${Quickshell.env("HOME")}/.local/state/aphotic`

    property var _holders: ({})
    property var _sessions: []

    readonly property bool _wanted: Object.keys(root._holders).length > 0

    function _ingest(line: string): void {
        let event;
        try {
            event = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (!event || !event.sessionId || !event.event)
            return;

        root._sessions = root.applyTo(root._sessions, event);
        root.record(event);
    }

    // Pure, and exported for the same reason AgentGraphService's fold is:
    // a consumer replaying a recorded run needs to rebuild state from a
    // list of events without touching the live one.
    function applyTo(existing: var, event: var): var {
        const sessions = existing.slice();
        let index = sessions.findIndex(s => s.id === event.sessionId);
        if (index === -1) {
            sessions.push({
                id: event.sessionId,
                harness: event.harness || "claude",
                status: "idle",
                model: event.model ?? "",
                cwd: event.cwd ?? "",
                tool: "",
                startedAt: event.t ?? 0,
                updatedAt: event.t ?? 0,
                endedAt: 0
            });
            index = sessions.length - 1;
        }

        const session = Object.assign({}, sessions[index]);
        session.updatedAt = event.t ?? session.updatedAt;
        if (event.cwd)
            session.cwd = event.cwd;
        if (event.model)
            session.model = event.model;
        if (event.harness)
            session.harness = event.harness;

        if (event.event === "session_end") {
            session.status = "ended";
            session.endedAt = event.t ?? 0;
        } else {
            session.endedAt = 0;
            if (event.event === "notification")
                session.status = "waiting";
            else if (event.event === "pre_tool_use" || event.event === "post_tool_use" || event.event === "post_tool_use_failure")
                session.status = "running";
            else
                session.status = "idle";
        }

        if (event.tool)
            session.tool = event.tool;

        sessions[index] = session;
        return sessions;
    }

    // Dropping everything on the last release, rather than keeping it
    // warm, is what makes a re-hold honest: the next surface to open gets
    // a state rebuilt from the tail's own backlog, not a snapshot frozen
    // at whatever moment the previous surface closed.
    onTailingChanged: {
        if (!root.tailing)
            root._sessions = [];
    }

    Process {
        id: eventTail

        running: root._wanted
        command: ["sh", "-c", `mkdir -p '${root._stateDir}' && : >> '${root._stateDir}/agent-events.jsonl' && exec tail -n ${root.historyLines} -F '${root._stateDir}/agent-events.jsonl'`]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root._ingest(data)
        }
    }

    Timer {
        interval: 30000
        running: root._wanted
        repeat: true
        onTriggered: {
            const cutoff = Date.now() - 300000;
            const kept = root._sessions.filter(s => s.status !== "ended" || s.endedAt > cutoff);
            if (kept.length !== root._sessions.length)
                root._sessions = kept;
        }
    }
}
