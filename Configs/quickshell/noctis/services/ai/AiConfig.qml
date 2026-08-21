pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Non-secret AI Chat settings, persisted to
// ~/.config/noctis/ai-config.json (same FileView load/save pattern as
// services/Settings.qml). Real API keys live in AiKeys.qml's separate,
// chmod-600 file instead -- see docs/COMMAND_CENTER.md §4.
Singleton {
    id: root

    readonly property string configPath: `${Quickshell.env("HOME")}/.config/noctis/ai-config.json`

    property string activeProvider: "ollama"
    property string ollamaHost: "http://10.0.0.200:11434"
    property string ollamaModel: "qwen3:30b"

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
            root._loaded = true;
        }
        onLoadFailed: error => {
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
        command: ["mkdir", "-p", `${Quickshell.env("HOME")}/.config/noctis`]
        onExited: configFile.reload()
    }

    Component.onCompleted: mkConfigDir.running = true
}
