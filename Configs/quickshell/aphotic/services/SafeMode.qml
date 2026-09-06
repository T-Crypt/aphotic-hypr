// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// One flag, read from one file the CLI writes (`aphotic safemode`,
// cmd_safemode.sh). While it is set, PluginRegistry hands out no
// registrations at all, so the shell comes up as core only -- the state
// a machine has to be able to reach when a plugin is what stops it
// starting. See docs/playbooks/safe-mode-recovery.md.
//
// Watched rather than read once, so leaving safe mode brings plugins
// back without a restart, and entering it drops them without one.
//
// The toast is the point of this being a singleton with behaviour rather
// than a plain flag: safe mode is invisible otherwise, and a user whose
// plugins are all missing with no explanation is worse off than one
// looking at a broken plugin.
Singleton {
    id: root

    readonly property string statePath: `${Quickshell.env("HOME")}/.local/state/aphotic/safe-mode.json`

    property bool active: false
    property string reason: ""
    property string since: ""

    property bool _announced: false

    function leave(): void {
        Quickshell.execDetached(["aphotic", "safemode", "off"]);
    }

    onActiveChanged: {
        if (!root.active) {
            root._announced = false;
            return;
        }
        if (root._announced)
            return;
        root._announced = true;
        Toaster.toast(qsTr("Safe mode"), root.reason ? qsTr("Plugins are held back: %1. Settings > System has the way out.").arg(root.reason) : qsTr("Plugins are held back. Settings > System has the way out."), "");
    }

    FileView {
        path: root.statePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.active = data.active === true;
                root.reason = data.reason ?? "";
                root.since = data.since ?? "";
            } catch (e) {
                root.active = false;
            }
        }
        onLoadFailed: {
            root.active = false;
            root.reason = "";
            root.since = "";
        }
    }
}
