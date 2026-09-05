// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton

import QtQuick
import Quickshell
import qs.services

// Which `fullscreen-overlay` surfaces (manifest v3.5) are on screen right
// now. One flag per trigger, read by shell.qml's host, which builds the
// windows when a surface becomes presented and destroys them when it
// stops -- teardown, not hide, so a surface that is not showing costs
// nothing at all.
//
// The trigger vocabulary is evaluated here rather than named in a
// manifest-shaped branch anywhere else, the same way PluginRegistry
// evaluates requires_layer. An unrecognised token is never presented: a
// plugin declaring a trigger this shell has never heard of was built
// against a newer contract, and showing it on the wrong signal is worse
// than not showing it.
//
// Locking wins over every fullscreen overlay. The lock is a session lock
// and already draws above these, so leaving one mounted underneath would
// be a surface animating where nobody can see it.
Singleton {
    id: root

    readonly property var triggers: ["idle", "manual"]

    property bool idle: false
    property var engaged: []

    function presented(surface: var): bool {
        if (SessionLockState.locked)
            return false;
        if (surface.trigger === "manual")
            return root.engaged.includes(surface.id);
        if (surface.trigger === "idle" || !surface.trigger)
            return root.idle;
        return false;
    }

    function engage(id: string): void {
        if (!root.engaged.includes(id))
            root.engaged = root.engaged.concat([id]);
    }

    function dismiss(surface: var): void {
        if (surface.trigger === "manual")
            root.engaged = root.engaged.filter(e => e !== surface.id);
        else
            root.idle = false;
    }

    function dismissAll(): void {
        root.idle = false;
        root.engaged = [];
    }
}
