// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

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

    // Every described harness in the user's order, each with its shown
    // flag: Settings.harnessEntries first, then any descriptor it doesn't
    // name yet, shown, in merge order. Entries for a harness with no
    // descriptor are skipped and kept, so a plugin disabled and enabled
    // again comes back where it was.
    readonly property var ordered: {
        const byId = new Map(root.harnesses.map(d => [d.id, d]));
        const out = [];
        for (const e of Settings.harnessEntries) {
            const d = byId.get(e.id);
            if (!d)
                continue;
            out.push({ descriptor: d, enabled: e.enabled });
            byId.delete(e.id);
        }
        for (const d of byId.values())
            out.push({ descriptor: d, enabled: true });
        return out;
    }

    // The shown harnesses in order. The first is the default.
    readonly property var visible: root.ordered.filter(o => o.enabled).map(o => o.descriptor)

    // Writes the whole order back, so entries for undescribed ids survive.
    function setOrder(entries: var): void {
        const named = new Set(entries.map(e => e.id));
        Settings.harnessEntries = entries.concat(Settings.harnessEntries.filter(e => !named.has(e.id)));
    }

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
