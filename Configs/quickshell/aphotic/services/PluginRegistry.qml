// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.ai

// Read-only view of ~/.local/state/aphotic/plugins.json's "installed"
// map (manifest v3 -- see docs/archive/PLUGIN_SYSTEM.md). The CLI
// (`aphotic plugin install|enable|disable|remove`, cmd_plugin.sh) is the
// only writer; this mirrors InstallProfile.qml's FileView load/watch
// pattern -- bash writes, QML watches, no round-trip. A plugin declaring
// a `ui-surface` capability shows up in surfaceRegistrations the instant
// it's installed+enabled, and drops out of it (reactively, same tick) the
// instant it's removed or disabled, which is what lets a UI-surface
// plugin's tab or tile disappear cleanly per §2.2's "no dead UI entries"
// requirement without the shell needing a static, compile-time import of
// that plugin's QML at all.
//
// ONE registry for every surface kind, not one per host. Dashboard tabs
// and notch tiles are the same record with a different `surface` value,
// so DashboardContent.qml and Notch.qml each filter the same list and
// neither knows any plugin's id. See docs/PLUGIN_LAYER_MODEL.md.
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

    // Every enabled plugin's [ui.*] declarations, resolved to absolute
    // file:// component URLs -- exactly the shape a dynamic
    // `Loader { source: ... }` needs, so the loading call site never has
    // to statically `import` a plugin's own QML. Installed+enabled only;
    // the per-surface activation gate is applied by surfacesFor(), not
    // here, so a caller can still see what a disabled-by-gate surface
    // would have been.
    readonly property var surfaceRegistrations: {
        const surfaces = [];
        for (const name of Object.keys(root._installed)) {
            if (!root.isEnabled(name))
                continue;
            for (const surface of root._surfacesOf(name))
                surfaces.push(surface);
        }
        return surfaces;
    }

    function surfacesFor(surface: string): var {
        return root.surfaceRegistrations.filter(s => s.surface === surface && root._gateSatisfied(s));
    }

    // A pre-`ui.surfaces` registry entry (written by a CLI older than the
    // surface unification) still carries a bare `dashboard_tab` object.
    // Reading it as one ungated dashboard surface keeps an install that
    // has not re-synced yet showing the tab it already had, rather than
    // silently losing it until the user runs an install they have no
    // reason to know they need. `aphotic plugin list` reports the entry
    // as drifted, which is the existing, visible path to re-syncing it.
    function _surfacesOf(name: string): var {
        const ui = root._installed[name]?.ui;
        if (!ui)
            return [];
        const declared = ui.surfaces ?? (ui.dashboard_tab ? [Object.assign({ surface: "dashboard" }, ui.dashboard_tab)] : []);
        return declared.filter(s => s && s.surface && s.component).map(s => ({
            plugin: name,
            surface: s.surface,
            id: s.id || name,
            icon: s.icon || "extension",
            label: s.label || name,
            requiresLayer: s.requires_layer ?? "",
            requiresData: s.requires_data ?? "",
            componentUrl: `file://${root.pluginsDir}/${name}/${s.component}`
        }));
    }

    function _gateSatisfied(surface: var): bool {
        return root._layerEnabled(surface.requiresLayer) && root._dataAvailable(surface.requiresData);
    }

    // An unrecognised token fails closed. A manifest naming a layer or a
    // data source this shell has never heard of is a plugin built against
    // a newer contract, and showing its surface anyway would mean showing
    // it with its gate silently dropped -- the one outcome the gate
    // exists to prevent.
    function _layerEnabled(layer: string): bool {
        if (!layer)
            return true;
        if (layer === "ai")
            return InstallProfile.aiEnabled;
        if (layer === "dev")
            return InstallProfile.devEnabled;
        if (layer === "gaming")
            return InstallProfile.gamingEnabled;
        if (layer === "security")
            return InstallProfile.securityEnabled;
        return false;
    }

    function _dataAvailable(source: string): bool {
        if (!source)
            return true;
        if (source === "harness")
            return AgentRoles.hasConfiguredHarness;
        return false;
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
