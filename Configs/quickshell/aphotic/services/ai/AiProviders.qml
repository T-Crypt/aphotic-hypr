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

    readonly property var _baseProviders: [
        { id: "ollama", label: "Ollama", requiresApiKey: false },
        { id: "claude", label: "Claude", requiresApiKey: true },
        { id: "gemini", label: "Gemini", requiresApiKey: true },
        { id: "chatgpt", label: "ChatGPT", requiresApiKey: true }
    ]
    // Pinned to the top of the list, and only present at all, once
    // installed -- there's no "not installed yet" pill to click; install.sh
    // is the only install path (NVIDIA-gated, opt-in), see AiConfig.qml.
    readonly property var providers: AiConfig.assistantEnabled ? [{ id: "assistant", label: "Aphotic Assistant", requiresApiKey: false }].concat(root._baseProviders) : root._baseProviders

    readonly property bool ollamaAvailable: AiConfig.ollamaHostConfigured
    readonly property bool assistantAvailable: AiConfig.assistantEnabled && AiConfig.ollamaHostConfigured
    readonly property bool claudeAvailable: AiKeys.hasAnthropicKey
    readonly property bool geminiAvailable: AiKeys.hasGeminiKey
    readonly property bool chatgptAvailable: AiKeys.hasOpenaiKey

    readonly property string assistantPromptPath: `${Quickshell.env("HOME")}/.config/aphotic/assistant-system-prompt.md`
    property string assistantSystemPrompt: ""

    FileView {
        id: assistantPromptFile

        path: root.assistantPromptPath
        watchChanges: true
        onLoaded: root.assistantSystemPrompt = text()
        onLoadFailed: error => root.assistantSystemPrompt = ""
    }

    property var ollamaModels: []
    property var ollamaRunningModels: []
    property bool pulling: false

    function refreshOllamaModels(): void {
        if (!AiConfig.ollamaHostConfigured) {
            root.ollamaModels = [];
            return;
        }
        ollamaModelsProc.command = ["curl", "-s", "-m", "5", `${AiConfig.ollamaHost}/api/tags`];
        ollamaModelsProc.running = true;
    }

    function refreshRunningModels(): void {
        if (!AiConfig.ollamaHostConfigured) {
            root.ollamaRunningModels = [];
            return;
        }
        ollamaPsProc.command = ["curl", "-s", "-m", "5", `${AiConfig.ollamaHost}/api/ps`];
        ollamaPsProc.running = true;
    }

    function deleteModel(name: string): void {
        ollamaDeleteProc.exec(["curl", "-s", "-m", "10", "-X", "DELETE", `${AiConfig.ollamaHost}/api/delete`, "-d", JSON.stringify({ name })]);
    }

    function pullModel(name: string): void {
        if (root.pulling)
            return;
        const trimmed = name.trim();
        if (trimmed.length === 0)
            return;
        root.pulling = true;
        ollamaPullProc.exec(["curl", "-s", "-X", "POST", `${AiConfig.ollamaHost}/api/pull`, "-d", JSON.stringify({ name: trimmed })]);
    }

    Connections {
        target: AiConfig
        function onOllamaHostChanged() {
            root.refreshOllamaModels();
            root.refreshRunningModels();
        }
    }

    Process {
        id: ollamaModelsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.ollamaModels = (data.models ?? []).map(m => m.name);
                } catch (e) {
                    // Host unreachable or unexpected response -- leave
                    // ollamaModels as-is rather than clearing a
                    // previously-successful list.
                }
            }
        }
    }

    // GET /api/ps -- currently-loaded (in-VRAM) models, separate from the
    // full installed-models list above.
    Process {
        id: ollamaPsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.ollamaRunningModels = (data.models ?? []).map(m => ({ name: m.name, size_vram: m.size_vram }));
                } catch (e) {
                    // Host unreachable or unexpected response -- leave
                    // ollamaRunningModels as-is.
                }
            }
        }
    }

    // DELETE /api/delete takes no response body worth parsing -- just
    // re-list the installed models once it's done.
    Process {
        id: ollamaDeleteProc
        onExited: root.refreshOllamaModels()
    }

    // POST /api/pull streams newline-delimited progress objects; we don't
    // render live progress, just a busy flag until the pull finishes.
    Process {
        id: ollamaPullProc
        onExited: {
            root.pulling = false;
            root.refreshOllamaModels();
        }
    }

    Component.onCompleted: root.refreshOllamaModels()

    function isAvailable(providerId: string): bool {
        switch (providerId) {
        case "ollama": return root.ollamaAvailable;
        case "assistant": return root.assistantAvailable;
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
    property string activeRequestId: ""

    signal responseReceived(string requestId, string text)
    signal errorReceived(string requestId, string message)

    // requestId lets multiple independent consumers (the dashboard AI Chat
    // tab, each Intelligence session) share this one singleton without
    // cross-talk -- every response/error echoes back the id its request
    // was sent under, so each consumer filters to its own. The provider
    // backend itself stays single-flight (one Process per provider type),
    // so a second sendMessage while busy is rejected the same way the
    // dashboard tab already disables its input on AiProviders.busy.
    function sendMessage(requestId: string, provider: string, model: string, text: string): void {
        if (root.busy)
            return;

        if ((provider === "ollama" || provider === "assistant") && !AiConfig.ollamaHostConfigured) {
            root.errorReceived(requestId, qsTr("No Ollama host configured. Set it in the model pill, or set OLLAMA_BASE_URL, to enable."));
            return;
        }
        if (!root.isAvailable(provider)) {
            const label = root.providers.find(p => p.id === provider)?.label ?? provider;
            root.errorReceived(requestId, qsTr("No API key configured for %1. Set %2 to enable.").arg(label).arg(root.requiredEnvVar(provider)));
            return;
        }

        root.busy = true;
        root.activeRequestId = requestId;

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
        default: {
            // Reached by both "ollama" and "assistant" -- the Assistant is
            // a persona/preset layered on this same Ollama call (pinned
            // model + a fixed system prompt), not a separate provider
            // type. root.assistantSystemPrompt is blank until install.sh's
            // setup_assistant renders it, so a manually-set
            // assistantEnabled with no rendered file just behaves like
            // plain Ollama with no system message.
            const isAssistant = provider === "assistant";
            const resolvedModel = isAssistant ? AiConfig.assistantModel : (model || AiConfig.ollamaModel);
            const messages = isAssistant && root.assistantSystemPrompt.length > 0 ? [{ role: "system", content: root.assistantSystemPrompt }, { role: "user", content: text }] : [{ role: "user", content: text }];
            ollamaProc.command = ["curl", "-s", "-m", "30",
                `${AiConfig.ollamaHost}/v1/chat/completions`,
                "-H", "content-type: application/json",
                "-d", JSON.stringify({ model: resolvedModel, messages })];
            ollamaProc.running = true;
            break;
        }
        }
    }

    function _finish(): void {
        root.busy = false;
    }

    Process {
        id: claudeProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.responseReceived(root.activeRequestId, text.trim());
                root._finish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0 && claudeProc.exitCode !== 0)
                    root.errorReceived(root.activeRequestId, text.trim());
            }
        }
    }

    Process {
        id: ollamaProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.responseReceived(root.activeRequestId, data.choices[0].message.content.trim());
                } catch (e) {
                    root.errorReceived(root.activeRequestId, `Ollama: unexpected response (${text.slice(0, 200)})`);
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
                    root.responseReceived(root.activeRequestId, data.candidates[0].content.parts[0].text.trim());
                } catch (e) {
                    root.errorReceived(root.activeRequestId, `Gemini: unexpected response (${text.slice(0, 200)})`);
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
                    root.responseReceived(root.activeRequestId, data.choices[0].message.content.trim());
                } catch (e) {
                    root.errorReceived(root.activeRequestId, `ChatGPT: unexpected response (${text.slice(0, 200)})`);
                }
                root._finish();
            }
        }
    }
}
