pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// API keys for AI Chat providers that need them (Claude, Gemini, ChatGPT).
// Kept in a separate, chmod-600 file from ai-config.json / shell.json --
// see docs/COMMAND_CENTER.md §4 for why keys don't belong in general
// shell config. Ollama needs no key (LAN host, direct HTTP).
Singleton {
    id: root

    readonly property string keysPath: `${Quickshell.env("HOME")}/.config/aphotic/ai-keys.json`

    property string anthropicApiKey: ""
    property string geminiApiKey: ""
    property string openaiApiKey: ""

    readonly property bool hasAnthropicKey: root.anthropicApiKey.length > 0
    readonly property bool hasGeminiKey: root.geminiApiKey.length > 0
    readonly property bool hasOpenaiKey: root.openaiApiKey.length > 0

    property bool _loaded: false

    function _save(): void {
        if (!root._loaded)
            return;
        keysWriter.setText(JSON.stringify({
            anthropicApiKey: root.anthropicApiKey,
            geminiApiKey: root.geminiApiKey,
            openaiApiKey: root.openaiApiKey
        }, null, 2));
        chmodProc.running = true;
    }

    onAnthropicApiKeyChanged: root._save()
    onGeminiApiKeyChanged: root._save()
    onOpenaiApiKeyChanged: root._save()

    FileView {
        id: keysFile

        path: root.keysPath
        watchChanges: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (typeof data.anthropicApiKey === "string")
                    root.anthropicApiKey = data.anthropicApiKey;
                if (typeof data.geminiApiKey === "string")
                    root.geminiApiKey = data.geminiApiKey;
                if (typeof data.openaiApiKey === "string")
                    root.openaiApiKey = data.openaiApiKey;
            } catch (e) {
                // No keys file yet, or malformed -- keep blanks above.
            }
            root._loaded = true;
        }
        onLoadFailed: error => {
            root._loaded = true;
        }
    }

    FileView {
        id: keysWriter

        path: root.keysPath
        printErrors: false
    }

    Process {
        id: chmodProc
        command: ["chmod", "600", root.keysPath]
    }

    Process {
        id: mkConfigDir
        command: ["mkdir", "-p", `${Quickshell.env("HOME")}/.config/aphotic`]
        onExited: keysFile.reload()
    }

    Component.onCompleted: mkConfigDir.running = true
}
