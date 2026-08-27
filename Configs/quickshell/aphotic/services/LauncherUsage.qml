pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Per-app launch counts for the launcher's app-search mode, biasing
// ranking toward frequently-launched apps -- same FileView load/save
// pattern as PinnedSnippets.qml (the closest existing precedent for
// small persisted launcher state). Plain frequency, no recency decay.
Singleton {
    id: root

    readonly property string statePath: `${Quickshell.env("HOME")}/.local/state/aphotic/launcher-usage.json`

    property var counts: ({})
    property bool _loaded: false
    property bool _writePending: false

    function recordLaunch(id: string): void {
        if (!id)
            return;
        const next = Object.assign({}, root.counts);
        next[id] = (next[id] ?? 0) + 1;
        root.counts = next;
        root._save();
    }

    function countFor(id: string): int {
        return root.counts[id] ?? 0;
    }

    function reset(): void {
        root.counts = {};
        root._save();
    }

    function _save(): void {
        if (!root._loaded)
            return;
        root._writePending = true;
        stateWriter.setText(JSON.stringify(root.counts));
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
                if (data && typeof data === "object" && !Array.isArray(data))
                    root.counts = data;
            } catch (e) {
                // First run / empty file -- keep the default empty map.
            }
            root._loaded = true;
        }
        onLoadFailed: error => root._loaded = true
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
