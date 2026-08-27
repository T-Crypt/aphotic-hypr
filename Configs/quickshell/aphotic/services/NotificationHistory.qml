pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Persistent notification history, layered on top of Notifs.qml without
// touching its toast pipeline -- watches Notifs.list for growth (new
// notifications are always prepended, so a length increase means
// list[0] is the new arrival) and copies the fields worth keeping into
// its own array, independent of NotifData's own lifecycle (NotifData.
// close() destroys the live object entirely; that must not erase history).
// Capped the same dual way IntelligenceSessions caps itself: a count
// limit and an age-based prune.
Singleton {
    id: root

    readonly property string statePath: `${Quickshell.env("HOME")}/.local/state/aphotic/notification-history.json`
    readonly property int maxEntries: 500
    readonly property int maxAgeDays: 30

    property var entries: []
    readonly property int unreadCount: root.entries.filter(e => !e.read).length

    property bool _loaded: false
    property bool _writePending: false
    property int _lastNotifsLength: -1

    function _prune(list: var): var {
        const cutoff = Date.now() - root.maxAgeDays * 24 * 60 * 60 * 1000;
        return list.filter(e => e.timestamp >= cutoff).slice(0, root.maxEntries);
    }

    function markRead(id: string): void {
        root.entries = root.entries.map(e => e.id === id && !e.read ? Object.assign({}, e, {
                    read: true
                }) : e);
        root._save();
    }

    function markAllRead(): void {
        root.entries = root.entries.map(e => e.read ? e : Object.assign({}, e, {
                    read: true
                }));
        root._save();
    }

    function deleteEntry(id: string): void {
        root.entries = root.entries.filter(e => e.id !== id);
        root._save();
    }

    function _record(n: var): void {
        const entry = {
            id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
            appName: n.appName,
            appIcon: n.appIcon,
            summary: n.summary,
            body: n.body,
            urgency: n.urgency,
            timestamp: Date.now(),
            read: false,
            actions: (n.actions ?? []).map(a => ({
                        identifier: a.identifier,
                        text: a.text
                    }))
        };
        root.entries = root._prune([entry, ...root.entries]);
        root._save();
    }

    function _save(): void {
        if (!root._loaded)
            return;
        root._writePending = true;
        stateWriter.setText(JSON.stringify(root.entries, null, 2));
    }

    Connections {
        target: Notifs
        function onListChanged() {
            const newLen = Notifs.list.length;
            if (root._lastNotifsLength >= 0 && newLen > root._lastNotifsLength)
                root._record(Notifs.list[0]);
            root._lastNotifsLength = newLen;
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
                if (Array.isArray(data))
                    root.entries = root._prune(data);
            } catch (e) {
                // No state file yet, or malformed -- start from empty history.
            }
            root._loaded = true;
            root._lastNotifsLength = Notifs.list.length;
        }
        onLoadFailed: error => {
            root._loaded = true;
            root._lastNotifsLength = Notifs.list.length;
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
