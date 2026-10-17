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

    // Every merged descriptor, in merge order (registry order for
    // plugins, then drop-in filenames). Consumers keep that order as
    // their tie-break; it is the record's own order.
    property var harnesses: []

    // The list the surfaces read. Every descriptor is visible for now;
    // the hidden and order settings are this property's one extension
    // point when the settings pane grows them.
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
                // Missing or torn: keep the last good record. The merge
                // writes atomically, so a bad read is always transient.
            }
        }
    }
}
