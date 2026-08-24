pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Persisted list of pinned clipboard entries, for snippets/commands
// reused often enough that they shouldn't fall out of cliphist's rolling
// history. Same FileView load/save pattern as services/Settings.qml.
Singleton {
    id: root

    readonly property string statePath: `${Quickshell.env("HOME")}/.local/state/aphotic/pinned-snippets.json`

    property list<var> entries: []
    property bool _loaded: false
    property bool _writePending: false

    function isPinned(raw: string): bool {
        return root.entries.some(e => e.raw === raw);
    }

    function toggle(raw: string, preview: string): void {
        if (root.isPinned(raw))
            root.entries = root.entries.filter(e => e.raw !== raw);
        else
            root.entries = [{
                raw: raw,
                preview: preview
            }, ...root.entries];
        root._save();
    }

    function _save(): void {
        if (!root._loaded)
            return;
        root._writePending = true;
        stateWriter.setText(JSON.stringify(root.entries));
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
                    root.entries = data.filter(e => typeof e?.raw === "string" && typeof e?.preview === "string");
            } catch (e) {
                // First run / empty file -- keep the default empty list.
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
