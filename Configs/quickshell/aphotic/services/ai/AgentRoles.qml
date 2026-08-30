// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Single source of harness/provider role + locality for every AI CLI this
// shell knows about. A harness (Claude Code, Codex, OpenCode, Gemini CLI)
// runs a session and executes tool calls; a provider (Ollama, unsloth, LM
// Studio, huggingface-cli) only serves inference and never gets its own
// Bar tab or Agent Graph node -- it's read as an annotation on whichever
// harness is using it as a backend. Optional [agents.<id>] tables in
// aphotic.toml override the built-in defaults below, read the same
// regex-over-known-keys way InstallProfile.qml reads [install].
Singleton {
    id: root

    readonly property var _defaults: [
        { id: "claude", label: "Claude Code", role: "harness", locality: null },
        { id: "codex", label: "Codex", role: "harness", locality: null },
        { id: "opencode", label: "OpenCode", role: "harness", locality: null },
        { id: "geminicli", label: "Gemini CLI", role: "harness", locality: null },
        { id: "ollama", label: "Ollama", role: "provider", locality: "local" },
        { id: "unsloth", label: "unsloth", role: "provider", locality: "local" },
        { id: "lms", label: "LM Studio", role: "provider", locality: "local" },
        { id: "huggingface-cli", label: "Hugging Face CLI", role: "provider", locality: "local" }
    ]

    property var _overrides: ({})

    readonly property var entries: root._defaults.map(d => {
        const o = root._overrides[d.id] ?? {};
        return {
            id: d.id,
            label: d.label,
            role: o.role ?? d.role,
            locality: d.locality,
            enabled: o.enabled ?? true
        };
    })

    readonly property var harnesses: root.entries.filter(e => e.role === "harness" && e.enabled)
    readonly property var providers: root.entries.filter(e => e.role === "provider" && e.enabled)

    function roleFor(id: string): string {
        return (root.entries.find(e => e.id === id) ?? {}).role ?? "";
    }

    function localityFor(id: string): string {
        return (root.entries.find(e => e.id === id) ?? {}).locality ?? "";
    }

    function isEnabled(id: string): bool {
        const e = root.entries.find(e => e.id === id);
        return e ? e.enabled : true;
    }

    FileView {
        path: `${Quickshell.env("HOME")}/Aphotic-Hypr/aphotic.toml`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const raw = text();
            const sectionRe = /\[agents\.([a-zA-Z0-9_-]+)\]\s*\n([^\[]*)/g;
            const next = {};
            let m;
            while ((m = sectionRe.exec(raw)) !== null) {
                const id = m[1];
                const body = m[2];
                const enabledMatch = body.match(/enabled\s*=\s*(true|false)/);
                const roleMatch = body.match(/role\s*=\s*"([^"]*)"/);
                const entry = {};
                if (enabledMatch)
                    entry.enabled = enabledMatch[1] === "true";
                if (roleMatch)
                    entry.role = roleMatch[1];
                next[id] = entry;
            }
            root._overrides = next;
        }
        onLoadFailed: {
            root._overrides = {};
        }
    }
}
