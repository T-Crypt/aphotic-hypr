pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services.ai

// Uniform interface over the four AI Chat providers. Claude is the only
// claude-CLI-subprocess-based provider; Ollama/Gemini/ChatGPT are direct
// HTTP clients via curl -- see docs/COMMAND_CENTER.md §4 for why (Ollama
// has no Anthropic-Messages-API-shaped endpoint, verified live).
Singleton {
    id: root

    readonly property var providers: [
        { id: "ollama", label: "Ollama", requiresApiKey: false },
        { id: "claude", label: "Claude", requiresApiKey: true },
        { id: "gemini", label: "Gemini", requiresApiKey: true },
        { id: "chatgpt", label: "ChatGPT", requiresApiKey: true }
    ]

    readonly property bool ollamaAvailable: true
    readonly property bool claudeAvailable: AiKeys.hasAnthropicKey
    readonly property bool geminiAvailable: AiKeys.hasGeminiKey
    readonly property bool chatgptAvailable: AiKeys.hasOpenaiKey

    function isAvailable(providerId: string): bool {
        switch (providerId) {
        case "ollama": return root.ollamaAvailable;
        case "claude": return root.claudeAvailable;
        case "gemini": return root.geminiAvailable;
        case "chatgpt": return root.chatgptAvailable;
        default: return false;
        }
    }

    // Env var each key-gated provider needs, surfaced in the "no key
    // configured" inline chat message so it tells the user exactly what
    // to set rather than failing silently or with a raw curl/CLI error.
    function requiredEnvVar(providerId: string): string {
        switch (providerId) {
        case "claude": return "ANTHROPIC_API_KEY";
        case "gemini": return "GEMINI_API_KEY";
        case "chatgpt": return "OPENAI_API_KEY";
        default: return "";
        }
    }

    property bool busy: false

    signal responseReceived(string text)
    signal errorReceived(string message)

    function sendMessage(text: string): void {
        if (root.busy)
            return;

        const provider = AiConfig.activeProvider;
        if (!root.isAvailable(provider)) {
            const label = root.providers.find(p => p.id === provider)?.label ?? provider;
            root.errorReceived(qsTr("No API key configured for %1. Set %2 to enable.").arg(label).arg(root.requiredEnvVar(provider)));
            return;
        }

        root.busy = true;

        switch (provider) {
        case "claude":
            claudeProc.command = ["claude", "-p", text, "--disallowed-tools", "*"];
            claudeProc.running = true;
            break;
        case "gemini":
            geminiProc.command = ["curl", "-s", "-m", "30",
                `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${AiKeys.geminiApiKey}`,
                "-H", "content-type: application/json",
                "-d", JSON.stringify({ contents: [{ parts: [{ text }] }] })];
            geminiProc.running = true;
            break;
        case "chatgpt":
            chatgptProc.command = ["curl", "-s", "-m", "30",
                "https://api.openai.com/v1/chat/completions",
                "-H", "content-type: application/json",
                "-H", `authorization: Bearer ${AiKeys.openaiApiKey}`,
                "-d", JSON.stringify({ model: "gpt-4o-mini", messages: [{ role: "user", content: text }] })];
            chatgptProc.running = true;
            break;
        default:
            ollamaProc.command = ["curl", "-s", "-m", "30",
                `${AiConfig.ollamaHost}/v1/chat/completions`,
                "-H", "content-type: application/json",
                "-d", JSON.stringify({ model: AiConfig.ollamaModel, messages: [{ role: "user", content: text }] })];
            ollamaProc.running = true;
            break;
        }
    }

    function _finish(): void {
        root.busy = false;
    }

    Process {
        id: claudeProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.responseReceived(text.trim());
                root._finish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0 && claudeProc.exitCode !== 0)
                    root.errorReceived(text.trim());
            }
        }
    }

    Process {
        id: ollamaProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.responseReceived(data.choices[0].message.content.trim());
                } catch (e) {
                    root.errorReceived(`Ollama: unexpected response (${text.slice(0, 200)})`);
                }
                root._finish();
            }
        }
    }

    Process {
        id: geminiProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.responseReceived(data.candidates[0].content.parts[0].text.trim());
                } catch (e) {
                    root.errorReceived(`Gemini: unexpected response (${text.slice(0, 200)})`);
                }
                root._finish();
            }
        }
    }

    Process {
        id: chatgptProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.responseReceived(data.choices[0].message.content.trim());
                } catch (e) {
                    root.errorReceived(`ChatGPT: unexpected response (${text.slice(0, 200)})`);
                }
                root._finish();
            }
        }
    }
}
