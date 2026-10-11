// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Single source for what the installer actually enabled. Feature surfaces
// read this instead of each one guessing from whether some state file
// happens to exist -- "the AI layer is off" has to mean the surface is
// absent, not present-but-empty.
Singleton {
    id: root

    readonly property string profile: root._profile
    readonly property var layers: root._layers
    readonly property bool known: root._known

    // The CLI keeps the data-dir link pointed at the checkout, whatever name
    // or case it was cloned under. Installs that predate the link fall back to
    // ~/Aphotic-Hypr until the next `aphotic` run creates it.
    readonly property string dotsDir: Quickshell.env("APHOTIC_DOTS_DIR") || (root._dotsLinked ? root._dotsLink : `${Quickshell.env("HOME")}/Aphotic-Hypr`)
    readonly property string version: root._version

    // Unknown is treated as enabled on purpose: a user running from a git
    // clone with no aphotic.toml yet should see the shell they cloned, not a
    // silently stripped one. Only an explicit config turns a layer off.
    readonly property bool aiEnabled: !root._known || root.hasLayer("ai")
    readonly property bool gamingEnabled: !root._known || root.hasLayer("gaming")
    readonly property bool devEnabled: !root._known || root.hasLayer("dev")

    // No `security` layer exists: the Security pillar's install-time
    // footprint is the exploit family (`exploit` plus its sublayers), and
    // a bare `security.toml` stub would be a file install.sh never offers
    // rather than real plumbing. If the pillar ever needs selecting
    // independently of the tooling, that is when the layer gets added --
    // with wizard wiring, not as a placeholder.
    readonly property bool securityEnabled: !root._known || root._layers.some(l => l === "exploit" || l.startsWith("exploit-"))

    property string _profile: ""
    property var _layers: []
    property bool _known: false
    readonly property string _dotsLink: `${Quickshell.env("XDG_DATA_HOME") || `${Quickshell.env("HOME")}/.local/share`}/aphotic/dots`
    property bool _dotsLinked: false
    property string _version: ""

    function hasLayer(name: string): bool {
        return root._layers.includes(name);
    }

    FileView {
        path: `${root._dotsLink}/VERSION`
        onLoaded: root._dotsLinked = true
        onLoadFailed: root._dotsLinked = false
    }

    FileView {
        path: `${root.dotsDir}/VERSION`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._version = text().trim()
        onLoadFailed: root._version = ""
    }

    FileView {
        path: `${root.dotsDir}/aphotic.toml`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const raw = text();
            root._profile = (raw.match(/profile\s*=\s*"([^"]*)"/) ?? [])[1] ?? "";
            const list = (raw.match(/layers\s*=\s*\[([^\]]*)\]/) ?? [])[1] ?? "";
            root._layers = list.split(",").map(v => v.replace(/["\s]/g, "")).filter(v => v.length > 0);
            root._known = true;
        }
        onLoadFailed: {
            root._profile = "";
            root._layers = [];
            root._known = false;
        }
    }
}
