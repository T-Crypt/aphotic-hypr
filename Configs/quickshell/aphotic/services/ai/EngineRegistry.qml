// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "EngineDescriptorCore.js" as Core

// One list of engine descriptors from three sources: a TOML file in this
// repo for an engine core supports, a TOML file under
// ~/.config/aphotic/engines/ for the operator's own engines, and an
// [engine] block a plugin carries in plugins.json. The parser and the
// precedence live in EngineDescriptorCore.js; this singleton owns the
// scan, reads the host store, and exposes the resolved list. Nothing
// consumes it in this slice, so no surface moves.
Singleton {
    id: root

    readonly property string enginesDir: `${InstallProfile.dotsDir}/Configs/quickshell/aphotic/services/ai/engines`
    readonly property string dropInDir: `${Quickshell.env("HOME")}/.config/aphotic/engines`
    readonly property string hostStorePath: `${Quickshell.env("HOME")}/.config/aphotic/engines.json`

    // The scan output, one record per file: {name, text}. The repo dir
    // ships empty, so a fresh install reads an empty core list.
    property var _core: []
    property var _dropIn: []
    property var _hosts: ({})

    // Highest tier first: a drop-in shadows a plugin, a plugin shadows
    // core, so resolve() sees the winner first. Warnings for a dropped
    // token and for a shadow both land in `warnings`.
    readonly property var _sources: root._buildSources()
    readonly property var resolved: Core.resolve(root._sources.descriptors)
    readonly property var descriptors: root.resolved.descriptors
    readonly property var shadowed: root.resolved.shadowed
    readonly property var warnings: root._sources.warnings.concat(root.resolved.warnings)

    function _buildSources(): var {
        const descriptors = [];
        const warnings = [];
        const add = (raw, source, sourceName) => {
            const result = Core.normalize(raw, source, sourceName);
            for (const line of result.warnings)
                warnings.push(line);
            if (result.descriptor)
                descriptors.push(result.descriptor);
        };
        for (const file of root._dropIn)
            add(Core.parse(file.text), "drop-in", file.name);
        for (const engine of PluginRegistry.engineRegistrations)
            add(engine, "plugin", engine.plugin);
        for (const file of root._core)
            add(Core.parse(file.text), "core", file.name);
        return { descriptors: descriptors, warnings: warnings };
    }

    function byId(id: string): var {
        return root.descriptors.find(d => d.id === id) ?? null;
    }

    function can(id: string, token: string): bool {
        const descriptor = root.byId(id);
        return descriptor !== null && descriptor.capabilities.includes(token);
    }

    // Host store first, then the legacy AiConfig property the descriptor's
    // host_key names (read-only, adopted on the way through), then the
    // descriptor's own default. Empty means "not configured".
    function baseUrl(id: string): string {
        const descriptor = root.byId(id);
        if (!descriptor)
            return "";
        const stored = root._hosts[id];
        if (typeof stored === "string" && stored.length > 0)
            return stored;
        const legacy = descriptor.hostKey.length > 0 ? AiConfig[descriptor.hostKey] : "";
        if (typeof legacy === "string" && legacy.length > 0)
            return legacy;
        return descriptor.defaultHost;
    }

    function setHost(id: string, url: string): void {
        const next = Object.assign({}, root._hosts);
        if (url.length > 0)
            next[id] = url;
        else
            delete next[id];
        root._hosts = next;
        hostWriter.setText(JSON.stringify({ hosts: next }, null, 2));
    }

    function reload(): void {
        scanProc.running = false;
        scanProc.running = true;
    }

    // One shell pipeline for both directories, framed the way Themes.qml
    // scans its theme dirs. A directory that does not exist expands to
    // itself, fails the -f test, and contributes nothing rather than
    // erroring -- a partial install must not lose every descriptor.
    Process {
        id: scanProc

        running: true
        command: ["sh", "-c", `for f in "$1"/*.toml; do [ -f "$f" ] || continue; printf 'CORE\\t%s\\n' "$(basename "$f")"; printf 'TEXT_BEGIN\\n'; cat "$f"; printf '\\nTEXT_END\\n'; done; for f in "$2"/*.toml; do [ -f "$f" ] || continue; printf 'DROP\\t%s\\n' "$(basename "$f")"; printf 'TEXT_BEGIN\\n'; cat "$f"; printf '\\nTEXT_END\\n'; done`, "aphotic-engines", root.enginesDir, root.dropInDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const core = [];
                const dropIn = [];
                let list = null;
                let name = "";
                let lines = null;
                for (const line of text.split("\n")) {
                    if (lines !== null) {
                        if (line === "TEXT_END") {
                            list.push({ name: name, text: lines.join("\n") });
                            lines = null;
                        } else {
                            lines.push(line);
                        }
                        continue;
                    }
                    if (line === "TEXT_BEGIN") {
                        lines = [];
                        continue;
                    }
                    const tab = line.indexOf("\t");
                    if (tab === -1)
                        continue;
                    const tag = line.slice(0, tab);
                    if (tag === "CORE") {
                        list = core;
                        name = line.slice(tab + 1);
                    } else if (tag === "DROP") {
                        list = dropIn;
                        name = line.slice(tab + 1);
                    }
                }
                root._core = core;
                root._dropIn = dropIn;
            }
        }
    }

    FileView {
        path: root.hostStorePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root._hosts = data && typeof data.hosts === "object" && data.hosts !== null ? data.hosts : ({});
            } catch (e) {
                // keep the last good host store
            }
        }
    }

    FileView {
        id: hostWriter

        path: root.hostStorePath
        printErrors: false
    }

    Process {
        id: mkConfigDir

        command: ["mkdir", "-p", `${Quickshell.env("HOME")}/.config/aphotic`]
        onExited: root.reload()
    }

    Component.onCompleted: mkConfigDir.running = true
}
