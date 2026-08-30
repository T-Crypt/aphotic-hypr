// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services.ai

// Single source of the harness/provider classification docs/archive/
// AGENT_TRACKING.md has referred to since before this file existed --
// see APHOTIC_UNIFIED_VISION.md §2.4 (Agent Graph's plugin activation
// gate) and §4.1 (the still-open AI-chat-surface role audit, which this
// file is a prerequisite for but does not itself complete).
Singleton {
    id: root

    // Static classification. Extend both lists when a new harness/
    // provider ships -- see AGENT_TRACKING.md §"Extending to another
    // harness".
    readonly property var harnessIds: ["claude", "codex", "opencode"]
    readonly property var providerIds: ["ollama", "gemini", "chatgpt"]

    function roleFor(id: string): string {
        if (root.harnessIds.includes(id))
            return "harness";
        if (root.providerIds.includes(id))
            return "provider";
        return "";
    }

    // "Configured" means a real, live availability signal, not just "the
    // id is classified as a harness above" -- a harness nobody has ever
    // logged into gives Agent Graph nothing to render. OpenCode has no
    // availability signal anywhere yet (AiProviders.qml has no entry for
    // it), so it can't contribute true here even though it's classified
    // as a harness above -- a known gap, not an oversight; see the
    // AI-chat-surface audit item in APHOTIC_UNIFIED_VISION.md §4.1.
    readonly property bool hasConfiguredHarness: AiProviders.claudeAvailable || AiProviders.codexAvailable
}
