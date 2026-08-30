// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Read-only view of ~/.local/state/aphotic/plugins.json's "installed"
// map (manifest v3 -- see docs/archive/PLUGIN_SYSTEM.md). The CLI
// (`aphotic plugin install|enable|disable|remove`, cmd_plugin.sh) is the
// only writer; this mirrors InstallProfile.qml's FileView load/watch
// pattern -- bash writes, QML watches, no round-trip. A plugin declaring
// a `ui-surface` capability shows up in dashboardTabs the instant it's
// installed+enabled, and drops out of it (reactively, same tick) the
// instant it's removed or disabled, which is what lets a UI-surface
// plugin's tab disappear cleanly per §2.2's "no dead UI entries"
// requirement without the shell needing a static, compile-time import
// of that plugin's QML at all.
Singleton {
    id: root

    readonly property string pluginsDir: `${Quickshell.env("HOME")}/.local/share/aphotic/plugins`

    readonly property var _disabled: root._data.disabled ?? []
    readonly property var _installed: root._data.installed ?? ({})

    property var _data: ({})

    function isInstalled(name: string): bool {
        return Object.prototype.hasOwnProperty.call(root._installed, name);
    }

    function isEnabled(name: string): bool {
        return root.isInstalled(name) && !root._disabled.includes(name);
    }

    // Every enabled plugin's [ui.dashboard_tab] declaration (plugin.toml,
    // manifest v3), resolved to an absolute file:// component URL --
    // exactly the shape a dynamic `Loader { source: ... }` needs, so the
    // loading call site never has to statically `import` a plugin's own
    // QML module.
    readonly property var dashboardTabs: {
        const tabs = [];
        for (const name of Object.keys(root._installed)) {
            if (!root.isEnabled(name))
                continue;
            const tab = root._installed[name]?.ui?.dashboard_tab;
            if (!tab || !tab.component)
                continue;
            tabs.push({
                plugin: name,
                id: tab.id ?? name,
                icon: tab.icon ?? "extension",
                label: tab.label ?? name,
                componentUrl: `file://${root.pluginsDir}/${name}/${tab.component}`
            });
        }
        return tabs;
    }

    FileView {
        path: `${Quickshell.env("HOME")}/.local/state/aphotic/plugins.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root._data = JSON.parse(text());
            } catch (e) {
                root._data = ({});
            }
        }
        onLoadFailed: root._data = ({})
    }
}
