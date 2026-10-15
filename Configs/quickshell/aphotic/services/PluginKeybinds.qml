// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// Every enabled plugin's declared combos, bound while those plugins are.
//
// One worker per registration rather than one per combo: each checks its
// own combo against the live bind table, so a conflict on one plugin's
// combo never holds back another's. Two plugins on one combo are already
// deduped in the registry, in registry order.
//
// The bind runs the same action the palette runs, through the same IPC
// entry point, so a plugin's action is registered once and reached two
// ways. `Actions.has` is the last word on whether the id still resolves:
// a registry entry naming an action that is not there binds nothing
// rather than swallowing the combo.
//
// This singleton acts on its own rather than answering a reader, so it
// needs a construction site in `shell.qml`'s `_residentSingletons` or
// none of the below ever runs.
Singleton {
    id: root

    readonly property var bindings: PluginRegistry.keybindRegistrations

    Instantiator {
        model: root.bindings

        delegate: PluginKeybind {
            required property var modelData

            combo: modelData.combo
            description: modelData.description
            command: `qs -c aphotic ipc call aphotic action ${modelData.id}`
            wanted: Actions.has(modelData.id)
        }
    }
}
