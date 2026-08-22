pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Non-secret AI Chat settings, persisted to
// ~/.config/aphotic/ai-config.json (same FileView load/save pattern as
// services/Settings.qml). Real API keys live in AiKeys.qml's separate,
// chmod-600 file instead -- see docs/COMMAND_CENTER.md §4.
Singleton {
    id: root

    readonly property string configPath: `${Quickshell.env("HOME")}/.config/aphotic/ai-config.json`

    // Blank by default -- deliberately NOT a real address. Every machine's
    // Ollama host is different (or absent entirely); baking in one user's
    // LAN IP would silently point everyone else's shell at somebody
    // else's server. See ollamaHostConfigured / the AI Chat tab's warning.
    property string activeProvider: "ollama"
    property string ollamaHost: ""
    property string ollamaModel: ""

    readonly property bool ollamaHostConfigured: root.ollamaHost.length > 0

    property bool _loaded: false

    function _save(): void {
        if (!root._loaded)
            return;
        configWriter.setText(JSON.stringify({
            activeProvider: root.activeProvider,
            ollamaHost: root.ollamaHost,
            ollamaModel: root.ollamaModel
        }, null, 2));
    }

    onActiveProviderChanged: root._save()
    onOllamaHostChanged: root._save()
    onOllamaModelChanged: root._save()

    FileView {
        id: configFile

        path: root.configPath
        watchChanges: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (typeof data.activeProvider === "string")
                    root.activeProvider = data.activeProvider;
                if (typeof data.ollamaHost === "string")
                    root.ollamaHost = data.ollamaHost;
                if (typeof data.ollamaModel === "string")
                    root.ollamaModel = data.ollamaModel;
            } catch (e) {
                // No config file yet, or malformed -- keep defaults above.
            }
            // No saved host yet -- fall back to OLLAMA_BASE_URL if the
            // environment sets one (matches Ollama's own tooling
            // convention), rather than staying blank when the user has
            // already told their shell about a host.
            if (!root.ollamaHost)
                root.ollamaHost = Quickshell.env("OLLAMA_BASE_URL") ?? "";
            root._loaded = true;
        }
        onLoadFailed: error => {
            if (!root.ollamaHost)
                root.ollamaHost = Quickshell.env("OLLAMA_BASE_URL") ?? "";
            root._loaded = true;
        }
    }

    FileView {
        id: configWriter

        path: root.configPath
        printErrors: false
    }

    Process {
        id: mkConfigDir
        command: ["mkdir", "-p", `${Quickshell.env("HOME")}/.config/aphotic`]
        onExited: configFile.reload()
    }

    Component.onCompleted: mkConfigDir.running = true
}
