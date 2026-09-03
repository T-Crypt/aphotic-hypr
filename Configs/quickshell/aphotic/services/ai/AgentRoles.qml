// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services.ai

// Single source of harness/provider role + locality for every AI CLI this
// shell knows about. A harness (Claude Code, Codex, OpenCode, Gemini CLI)
// runs a session and executes tool calls; a provider (Ollama, unsloth, LM
// Studio, huggingface-cli) only serves inference and never gets its own
// Bar tab or Agent Graph node -- it's read as an annotation on whichever
// harness is using it as a backend. Optional [agents.<id>] tables in
// aphotic.toml override the built-in defaults below, read the same
// regex-over-known-keys way InstallProfile.qml reads [install].
//
// Merged from two independent implementations that landed on either side
// of the `main`/`modular` split (reconciled 2026-08-30): `main`'s richer
// entries/overrides/locality model (this file's bulk) plus `modular`'s
// `hasConfiguredHarness` gate, which the Agent Graph plugin's own
// activation rule depends on (see docs/archive/PLUGIN_SYSTEM.md's worked
// example and APHOTIC_UNIFIED_VISION.md §2.4) and which `main` never
// needed since it has no plugin-activation concept.
Singleton {
    id: root

    // `chat` is a separate axis from `role`, not a synonym for it: a
    // harness can also be a first-class conversational model, and Claude is
    // exactly that -- you can chat with Claude or you can drive Claude Code,
    // and both are Anthropic-supported uses of the same CLI session. So the
    // two roles are not mutually exclusive, and collapsing them into one
    // field would misrepresent Claude either way round.
    //
    // Codex, OpenCode and Gemini CLI are harnesses only. They run sessions
    // and execute tool calls; there is no plain "talk to it" mode behind
    // them, so they must not be offered as chat providers (§4.1). Providers
    // serve inference by definition, so `chat` defaults true for them.
    readonly property var _defaults: [
        { id: "claude", label: "Claude Code", role: "harness", chat: true, locality: null },
        { id: "codex", label: "Codex", role: "harness", chat: false, locality: null },
        { id: "opencode", label: "OpenCode", role: "harness", chat: false, locality: null },
        { id: "geminicli", label: "Gemini CLI", role: "harness", chat: false, locality: null },
        { id: "ollama", label: "Ollama", role: "provider", chat: true, locality: "local" },
        // Off unless aphotic.toml opts in with `[agents.unsloth] enabled =
        // true`. It runs GGUF weights directly rather than through Ollama's
        // model store, so it is a genuinely separate local backend -- but
        // one nobody gets a pill for by default.
        { id: "unsloth", label: "Unsloth", role: "provider", chat: true, enabled: false, locality: "local" },
        { id: "lms", label: "LM Studio", role: "provider", chat: true, locality: "local" },
        { id: "huggingface-cli", label: "Hugging Face CLI", role: "provider", chat: true, locality: "local" }
    ]

    property var _overrides: ({})

    readonly property var entries: root._defaults.map(d => {
        const o = root._overrides[d.id] ?? {};
        return {
            id: d.id,
            label: d.label,
            role: o.role ?? d.role,
            chat: o.chat ?? d.chat,
            locality: d.locality,
            enabled: o.enabled ?? d.enabled ?? true
        };
    })

    readonly property var harnesses: root.entries.filter(e => e.role === "harness" && e.enabled)
    readonly property var providers: root.entries.filter(e => e.role === "provider" && e.enabled)

    function roleFor(id: string): string {
        return (root.entries.find(e => e.id === id) ?? {}).role ?? "";
    }

    // Whether this id may be offered as a selectable chat provider. Ids this
    // classifier has never heard of pass -- Gemini and ChatGPT are raw HTTP
    // APIs with no CLI behind them (distinct from the `geminicli` harness
    // above), and the Aphotic Assistant is a local model, so none of them
    // are agent-tracking concerns at all and none belong in _defaults.
    function servesChat(id: string): bool {
        const e = root.entries.find(e => e.id === id);
        return e ? e.chat === true : true;
    }

    function localityFor(id: string): string {
        return (root.entries.find(e => e.id === id) ?? {}).locality ?? "";
    }

    function isEnabled(id: string): bool {
        const e = root.entries.find(e => e.id === id);
        return e ? e.enabled : true;
    }

    // "Configured" means a real, live availability signal, not just "the
    // id is classified as a harness above" -- a harness nobody has ever
    // logged into gives Agent Graph nothing to render. OpenCode has no
    // availability signal anywhere yet (AiProviders.qml has no entry for
    // it), so it can't contribute true here even though it's classified
    // as a harness above -- a known gap, not an oversight; see the
    // AI-chat-surface audit item in APHOTIC_UNIFIED_VISION.md §4.1.
    readonly property bool hasConfiguredHarness: AiProviders.claudeAvailable || AiProviders.codexAvailable

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
                const chatMatch = body.match(/chat\s*=\s*(true|false)/);
                const entry = {};
                if (enabledMatch)
                    entry.enabled = enabledMatch[1] === "true";
                if (roleMatch)
                    entry.role = roleMatch[1];
                if (chatMatch)
                    entry.chat = chatMatch[1] === "true";
                next[id] = entry;
            }
            root._overrides = next;
        }
        onLoadFailed: {
            root._overrides = {};
        }
    }
}
