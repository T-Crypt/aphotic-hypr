pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.ai

// Conversation history for the Intelligence quick-chat popout, persisted to
// ~/.local/state/aphotic/intelligence-sessions.json (same FileView
// load/save/_writePending pattern as services/Settings.qml -- ai-config.json
// only ever tracked the dashboard AI Chat tab's active provider/host/model,
// never message history, so this is new state, not an extension of it.
// Also owns send orchestration (not just storage): responses route back to
// the session they were sent from by requestId, not to whichever session
// happens to be visible, so a reply still lands correctly even if the user
// switched sessions -- or closed the panel entirely -- while it was in
// flight.
Singleton {
    id: root

    readonly property string statePath: `${Quickshell.env("HOME")}/.local/state/aphotic/intelligence-sessions.json`

    property var sessions: []
    property string activeSessionId: ""

    readonly property var activeSession: root.sessions.find(s => s.id === root.activeSessionId) ?? null

    property bool _loaded: false
    property bool _writePending: false

    function _makeId(): string {
        return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
    }

    function createSession(provider: string, model: string): string {
        const now = Date.now();
        const session = {
            id: root._makeId(),
            title: qsTr("New chat"),
            provider,
            model,
            createdAt: now,
            updatedAt: now,
            messages: []
        };
        root.sessions = [session, ...root.sessions];
        root.activeSessionId = session.id;
        root._save();
        root._enforceLimits();
        return session.id;
    }

    function _enforceLimits(): void {
        root.pruneExcess(Settings.intelligenceMaxSessions);
        root.pruneOlderThan(Settings.intelligenceAutoPruneDays);
    }

    function switchSession(id: string): void {
        if (root.sessions.some(s => s.id === id))
            root.activeSessionId = id;
    }

    function deleteSession(id: string): void {
        root.sessions = root.sessions.filter(s => s.id !== id);
        if (root.activeSessionId === id)
            root.activeSessionId = root.sessions[0]?.id ?? "";
        root._save();
    }

    function renameSession(id: string, title: string): void {
        root.sessions = root.sessions.map(s => s.id === id ? { id: s.id, title, provider: s.provider, model: s.model, createdAt: s.createdAt, updatedAt: s.updatedAt, messages: s.messages } : s);
        root._save();
    }

    function setSessionProvider(id: string, provider: string, model: string): void {
        root.sessions = root.sessions.map(s => s.id === id ? { id: s.id, title: s.title, provider, model, createdAt: s.createdAt, updatedAt: s.updatedAt, messages: s.messages } : s);
        root._save();
    }

    function appendMessage(id: string, role: string, text: string): void {
        const now = Date.now();
        root.sessions = root.sessions.map(s => {
            if (s.id !== id)
                return s;
            const messages = s.messages.concat([{ role, text, createdAt: now }]);
            const title = s.messages.length === 0 && role === "user" ? text.slice(0, 60) : s.title;
            return { id: s.id, title, provider: s.provider, model: s.model, createdAt: s.createdAt, updatedAt: now, messages };
        });
        root._save();
    }

    // Ensures a session exists to send into -- creates one from the given
    // fallback provider/model if there's no active session yet (e.g. first
    // open after install, or every session got pruned/deleted), rather than
    // silently no-opping the send.
    function sendUserMessage(text: string, fallbackProvider: string, fallbackModel: string): void {
        let id = root.activeSessionId;
        if (!root.activeSession)
            id = root.createSession(fallbackProvider, fallbackModel);

        const session = root.sessions.find(s => s.id === id);
        if (!session)
            return;

        root.appendMessage(id, "user", text);
        AiProviders.sendMessage(id, session.provider, session.model, text);
    }

    function pruneExcess(maxSessions: int): void {
        if (maxSessions <= 0 || root.sessions.length <= maxSessions)
            return;
        root.sessions = root.sessions.slice(0, maxSessions);
        if (!root.sessions.some(s => s.id === root.activeSessionId))
            root.activeSessionId = root.sessions[0]?.id ?? "";
        root._save();
    }

    function pruneOlderThan(days: int): void {
        if (days <= 0)
            return;
        const cutoff = Date.now() - days * 86400000;
        root.sessions = root.sessions.filter(s => s.updatedAt >= cutoff);
        if (!root.sessions.some(s => s.id === root.activeSessionId))
            root.activeSessionId = root.sessions[0]?.id ?? "";
        root._save();
    }

    function _save(): void {
        if (!root._loaded)
            return;
        root._writePending = true;
        stateWriter.setText(JSON.stringify({
            sessions: root.sessions,
            activeSessionId: root.activeSessionId
        }, null, 2));
    }

    Connections {
        target: AiProviders
        function onResponseReceived(requestId, text) {
            if (root.sessions.some(s => s.id === requestId))
                root.appendMessage(requestId, "assistant", text);
        }
        function onErrorReceived(requestId, message) {
            if (root.sessions.some(s => s.id === requestId))
                root.appendMessage(requestId, "assistant", `⚠ ${message}`);
        }
    }

    FileView {
        id: stateFile

        path: root.statePath
        watchChanges: true
        onLoaded: {
            if (root._writePending) {
                root._writePending = false;
                return;
            }
            try {
                const data = JSON.parse(text());
                if (Array.isArray(data.sessions))
                    root.sessions = data.sessions;
                if (typeof data.activeSessionId === "string")
                    root.activeSessionId = data.activeSessionId;
            } catch (e) {
                // No state file yet, or malformed -- start with an empty
                // session list rather than blocking load.
            }
            root._loaded = true;
            root._enforceLimits();
        }
        onLoadFailed: error => {
            root._loaded = true;
        }
    }

    FileView {
        id: stateWriter

        path: root.statePath
        printErrors: false
    }

    Process {
        id: mkStateDir
        command: ["mkdir", "-p", `${Quickshell.env("HOME")}/.local/state/aphotic`]
        onExited: stateFile.reload()
    }

    Component.onCompleted: mkStateDir.running = true
}
