// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// The merged harness descriptor record in memory: one reader of
// ~/.local/state/aphotic/harnesses.json, which the merge
// (Configs/.local/lib/aphotic/harnesses_merge.py, run by
// `aphotic agent harnesses`) writes atomically. Bash writes, QML
// watches, the same shape plugins.json uses.
//
// This is the only QML file that knows the record's field names. The
// merge already validated every descriptor and dropped the malformed
// ones, so nothing here re-checks a field: a torn read or a missing
// file keeps the last good record, and the next merge reloads it.
Singleton {
    id: root

    readonly property string _recordPath: `${Quickshell.env("HOME")}/.local/state/aphotic/harnesses.json`

    property var harnesses: []

    readonly property var visible: root.harnesses

    // The descriptor claiming the id, or null when no descriptor does:
    // how a reader tells an opted-in harness from a stray id.
    function descriptorOf(id: string): var {
        const found = root.harnesses.find(d => d.id === id);
        return found ?? null;
    }

    FileView {
        path: root._recordPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (data.schemaVersion !== 1)
                    return;
                root.harnesses = data.harnesses ?? [];
            } catch (e) {
            }
        }
    }
}
