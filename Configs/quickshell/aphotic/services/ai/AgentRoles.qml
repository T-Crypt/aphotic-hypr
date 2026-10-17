// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.ai

// Single source of harness/provider role + locality for every AI CLI this
// shell knows about. A harness runs a session and executes tool calls; a
// provider (Ollama, Studio, huggingface-cli) only serves inference and
// never gets its own Bar tab or Agent Graph node -- it's read as an
// annotation on whichever harness is using it as a backend. Harness rows
// come from the merged descriptor record (Harnesses), so this file never
// names a harness: the built-in table below holds provider rows only, and
// a harness row is whatever descriptor the machine declares. Optional
// [agents.<id>] tables in aphotic.toml override the provider rows only,
// read the same regex-over-known-keys way InstallProfile.qml reads
// [install].
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
    // A harness whose descriptor sets chat to false (or leaves it out) is
    // a session runner with no plain "talk to it" mode, so it must not be
    // offered as a chat provider (§4.1). Providers serve inference by
    // definition, so `chat` defaults true for them.
    //
    // Provider rows only: the built-in harness rows left with the descriptor
    // record, so a harness exists here if and only if its descriptor is
    // installed (Harnesses.harnesses below).
    readonly property var _defaults: [
        { id: "ollama", label: "Ollama", role: "provider", chat: true, locality: "local" },
        { id: "llama-swap", label: "llama-swap", role: "provider", chat: false, locality: "local" },
        // Off unless aphotic.toml opts in with `[agents.unsloth] enabled =
        // true`. It runs GGUF weights directly rather than through Ollama's
        // model store, so it is a genuinely separate local backend -- but
        // one nobody gets a pill for by default.
        { id: "unsloth", label: "Unsloth", role: "provider", chat: true, enabled: false, locality: "local" },
        { id: "lms", label: "LM Studio", role: "provider", chat: true, locality: "local" },
        { id: "huggingface-cli", label: "Hugging Face CLI", role: "provider", chat: true, locality: "local" }
    ]

    property var _overrides: ({})

    // Harness rows are the descriptors themselves, not a table this file
    // keeps in sync: a descriptor is the opt-in, so it is on, and its
    // chat flag is the descriptor's own.
    readonly property var harnessRows: Harnesses.harnesses.map(h => ({
        id: h.id,
        label: h.label,
        role: "harness",
        chat: h.chat,
        enabled: true
    }))

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
    }).concat(root.harnessRows)

    readonly property var harnesses: root.entries.filter(e => e.role === "harness" && e.enabled)
    readonly property var providers: root.entries.filter(e => e.role === "provider" && e.enabled)

    function roleFor(id: string): string {
        return (root.entries.find(e => e.id === id) ?? {}).role ?? "";
    }

    // Whether this id may be offered as a selectable chat provider. The
    // classifier fails closed: an id with no row above and no descriptor
    // is not a chat provider, which is what keeps a retired harness row
    // from reading as one once it leaves _defaults. Gemini and ChatGPT are
    // the exception: raw HTTP APIs with no CLI behind them, so they have
    // neither row nor descriptor and are named here rather than passing as
    // unknown (the Aphotic Assistant is built into AiProviders, never
    // classified).
    readonly property var _chatApis: ["gemini", "chatgpt"]

    function servesChat(id: string): bool {
        const e = root.entries.find(e => e.id === id);
        if (e)
            return e.chat === true;
        return root._chatApis.includes(id);
    }

    function localityFor(id: string): string {
        return (root.entries.find(e => e.id === id) ?? {}).locality ?? "";
    }

    function isEnabled(id: string): bool {
        const e = root.entries.find(e => e.id === id);
        return e ? e.enabled : true;
    }

    // "Configured" means the user opted a harness in: a descriptor is the
    // opt-in and it is the only signal this gate reads. The two chat-axis
    // login probes keep running for the chat surfaces and no longer feed
    // the gate, so an OpenCode-only machine -- or a custom drop-in
    // harness -- opens the same surfaces a Claude machine does, and a
    // machine with no descriptor answers false and stays gated off.
    readonly property bool hasConfiguredHarness: Harnesses.harnesses.length > 0

    // Display casing for harness codename models. A codename cannot be
    // derived from its id -- "sol" is styled SOL and "luna" is styled Luna
    // -- so the ones we have seen are listed and anything new falls back to
    // title case rather than being rendered wrong with confidence.
    readonly property var _codenames: ({
        "sol": "SOL",
        "luna": "Luna",
        "terra": "Terra",
        "astra": "Astra"
    })

    // Suffixes that size a model rather than name it. These read as
    // "GPT-5.4 mini", never "Mini 5.4", so they must not be mistaken for a
    // codename.
    readonly property var _tiers: ["mini", "nano", "pro", "codex", "turbo", "preview"]

    function labelFor(id: string): string {
        return (root.entries.find(e => e.id === id) ?? {}).label ?? id;
    }

    // A model id turned into what a person calls the thing. Pure string
    // work on purpose: the shell has no network and cannot ask a provider
    // for a display name, so this has to hold up on ids released long
    // after it was written. `provider` is the backend actually serving the
    // weights, "" when nothing is known about it.
    function modelDisplayName(raw: string, provider: string): string {
        const id = (raw ?? "").trim();
        if (!id)
            return "";

        // Locally served weights are named by the weights, not by a vendor
        // family: the provider is the useful half of "who is answering",
        // since the same GGUF can be served by any of them.
        if (provider && root.localityFor(provider) === "local") {
            let base = id.split(":")[0];
            const slash = base.lastIndexOf("/");
            if (slash !== -1)
                base = base.slice(slash + 1);
            return base ? `${provider}/${base}` : provider;
        }

        // Trailing context-window variant, e.g. "[1m]". It is a property of
        // the session, not of the model, and it shows in the raw id on hover.
        const bare = id.replace(/\[[^\]]*\]\s*$/, "");

        const claude = bare.match(/^claude-([a-z]+)-(.+)$/i);
        if (claude) {
            const family = claude[1];
            // A dated snapshot suffix is release bookkeeping, not a version.
            const version = claude[2].replace(/-\d{6,8}$/, "").split("-").join(".");
            return `${family.charAt(0).toUpperCase()}${family.slice(1)} ${version}`;
        }

        const gpt = bare.match(/^gpt-([0-9]+(?:\.[0-9]+)*)(?:-(.+))?$/i);
        if (gpt) {
            const version = gpt[1];
            const suffix = (gpt[2] ?? "").toLowerCase();
            if (!suffix)
                return `GPT-${version}`;
            if (root._tiers.includes(suffix))
                return `GPT-${version} ${suffix}`;
            const named = root._codenames[suffix]
                ?? `${suffix.charAt(0).toUpperCase()}${suffix.slice(1)}`;
            return `${named} ${version}`;
        }

        return bare;
    }

    FileView {
        path: `${InstallProfile.dotsDir}/aphotic.toml`
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
            // Overrides are provider-row only now: a table for a harness id
            // is ignored, with a migration pointer for one release.
            for (const h of Harnesses.harnesses) {
                if (next[h.id])
                    console.warn(`aphotic agents: [agents.${h.id}] is a harness id and is ignored; declare it in ${Quickshell.env("HOME")}/.config/aphotic/harnesses/${h.id}.toml`);
            }
        }
        onLoadFailed: {
            root._overrides = {};
        }
    }
}
