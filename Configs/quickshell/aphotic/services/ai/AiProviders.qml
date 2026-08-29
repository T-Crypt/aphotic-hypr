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
        { id: "claude", label: "Claude", requiresApiKey: false },
        // "Codex" is the CLI-subprocess sibling of "Claude" (its own login
        // session, not an API key -- see codexAvailable below), distinct
        // from "ChatGPT" below, which stays a real, separate raw-HTTP
        // provider that genuinely needs an API key. Codex's own OAuth
        // session isn't a usable bearer token for the public
        // api.openai.com REST API any more than claude.ai's own session
        // would be for api.anthropic.com -- conflating the two would have
        // been architecturally wrong, not just a naming choice.
        { id: "codex", label: "Codex", requiresApiKey: false },
        { id: "gemini", label: "Gemini", requiresApiKey: true },
        { id: "chatgpt", label: "ChatGPT", requiresApiKey: true }
    ]
    // Pinned to the top of the list, and only present at all, once
    // installed -- there's no "not installed yet" pill to click; install.sh
    // is the only install path (NVIDIA-gated, opt-in), see AiConfig.qml.
    readonly property var providers: AiConfig.assistantEnabled ? [{ id: "assistant", label: "Aphotic Assistant", requiresApiKey: false }].concat(root._baseProviders) : root._baseProviders

    readonly property bool ollamaAvailable: AiConfig.ollamaHostConfigured
    readonly property bool assistantAvailable: AiConfig.assistantEnabled && AiConfig.ollamaHostConfigured
    // Real bug fixed 2026-08-29: this used to be AiKeys.hasAnthropicKey --
    // requiring a SEPARATE API key stored in Aphotic's own ai-keys.json
    // before Claude would even show as available. But sendMessage()'s
    // claude branch (below) never actually reads that key at all -- it
    // just runs the `claude` CLI subprocess, which has its own real,
    // independent login session (`claude auth status`, a genuine
    // claude.ai OAuth-style session, not an API key at all -- confirmed
    // live on this machine: loggedIn:true, authMethod:"claude.ai",
    // apiProvider:"firstParty"). So the old gate could show Claude as
    // UNAVAILABLE on a machine where `claude` was already fully logged in
    // and perfectly able to answer, purely because nobody had also typed
    // a redundant API key into a second, Aphotic-specific field. Now
    // checks the CLI's own real auth state instead -- see
    // claudeLoggedIn/refreshClaudeAuth below.
    readonly property bool claudeAvailable: root.claudeLoggedIn
    // UNVERIFIED (2026-08-29): `codex` isn't installed on this machine
    // (confirmed: `command -v codex` fails, and it's in neither the
    // official repos nor AUR under that exact name) and there was no
    // real binary to test the actual auth-status command/output shape
    // against, unlike claudeAvailable above, which WAS verified live.
    // `codex login status` and the exec-mode invocation in sendMessage()
    // below are both a good-faith best guess at OpenAI's real Codex CLI
    // surface, not confirmed. Treat this the same way the rest of this
    // session treats an unverified fix: real risk it's wrong, needs a
    // live check against the actual installed binary before trusting it
    // -- see docs/LEDGER.md.
    readonly property bool codexAvailable: root.codexLoggedIn
    readonly property bool geminiAvailable: AiKeys.hasGeminiKey
    readonly property bool chatgptAvailable: AiKeys.hasOpenaiKey

    property bool claudeCliPresent: false
    property bool claudeLoggedIn: false
    property bool codexCliPresent: false
    property bool codexLoggedIn: false

    // Re-checkable on demand (the Settings pane calls this on a manual
    // refresh) since logging in happens outside this shell entirely (a
    // real `claude login`/`codex login` in a terminal) -- there's no live
    // signal this process could otherwise observe to know the moment
    // that finishes.
    function refreshClaudeAuth(): void {
        claudeAuthProc.running = true;
    }

    function refreshCodexAuth(): void {
        codexAuthProc.running = true;
    }

    Process {
        id: claudeAuthProc
        command: ["claude", "auth", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.claudeCliPresent = true;
                try {
                    const data = JSON.parse(text);
                    root.claudeLoggedIn = data.loggedIn === true;
                } catch (e) {
                    root.claudeLoggedIn = false;
                }
            }
        }
        onExited: exitCode => {
            // A nonzero exit with no stdout at all (command not found,
            // or a real failure before the CLI could print its own JSON)
            // means neither "present" nor "logged in" claims hold --
            // stdout's own handler above already covers the case where
            // it exited nonzero but still printed a real (loggedIn:false)
            // status, which is a legitimate "present, not logged in"
            // result, not an error.
            if (exitCode !== 0 && !root.claudeCliPresent)
                root.claudeLoggedIn = false;
        }
    }

    // See codexAvailable's comment above -- `codex login status` and its
    // JSON output shape are a best-effort guess, not confirmed against a
    // real binary. Written defensively (checks a couple of plausible key
    // names) so a close-but-not-exact real output shape has a chance of
    // still working, but this needs a real live test before it's trusted.
    Process {
        id: codexAuthProc
        command: ["codex", "login", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.codexCliPresent = true;
                try {
                    const data = JSON.parse(text);
                    root.codexLoggedIn = data.loggedIn === true || data.logged_in === true || data.authenticated === true;
                } catch (e) {
                    // Some CLI status subcommands print human-readable
                    // text instead of JSON -- a plain substring check as
                    // a last resort, still better than assuming false.
                    root.codexLoggedIn = /logged in|authenticated/i.test(text) && !/not logged in|not authenticated/i.test(text);
                }
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0 && !root.codexCliPresent)
                root.codexLoggedIn = false;
        }
    }

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
    // Real reachability signal, separate from ollamaHostConfigured (which
    // only means "a host STRING is set," not "something is actually
    // listening there"). refreshOllamaModels()'s old catch-and-ignore
    // behavior deliberately never cleared ollamaModels on failure (so a
    // transient blip doesn't wipe a previously-successful list), which
    // means it also never gave any OTHER consumer a way to tell "still
    // reachable" from "was reachable once, isn't now" -- this property
    // is that missing signal, updated explicitly on every attempt.
    property bool ollamaReachable: false
    property bool startingOllama: false

    function refreshOllamaModels(): void {
        if (!AiConfig.ollamaHostConfigured) {
            root.ollamaModels = [];
            root.ollamaReachable = false;
            return;
        }
        ollamaModelsProc.command = ["curl", "-s", "-m", "5", `${AiConfig.ollamaHost}/api/tags`];
        ollamaModelsProc.running = true;
    }

    // Ollama's own systemd unit (ollama.service) is a SYSTEM service --
    // (re)starting it needs root, which this shell deliberately never
    // requests live (install.sh is the only place that asks for sudo,
    // once, interactively, at install time -- see lib/install/
    // assistant.sh). Running the plain `ollama serve` binary directly as
    // a normal detached user process needs no privilege at all and is
    // exactly what someone would do by hand in a terminal if the service
    // wasn't already up -- Ollama fully supports being run this way, it's
    // not a workaround. If ollama.service (or an earlier `ollama serve`)
    // is already bound to the port, this just fails to bind and exits;
    // refreshOllamaModels() below is what actually confirms success, not
    // this process's own exit code.
    function startOllama(): void {
        if (root.startingOllama || root.ollamaReachable)
            return;
        root.startingOllama = true;
        Quickshell.execDetached(["ollama", "serve"]);
        ollamaStartupRetry.restart();
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
                    root.ollamaReachable = true;
                    root.startingOllama = false;
                } catch (e) {
                    // Host unreachable or unexpected response -- leave
                    // ollamaModels as-is rather than clearing a
                    // previously-successful list, but ollamaReachable
                    // DOES flip false here -- it's the real up-to-date
                    // signal (see its own declaration above), unlike the
                    // stale-on-purpose model list.
                    root.ollamaReachable = false;
                }
            }
        }
    }

    // Polls a few times after startOllama() launches the process, since
    // `ollama serve` binding its port and becoming ready to answer
    // requests isn't instant -- a single immediate refresh would almost
    // always still see "unreachable" and clear startingOllama's spinner
    // right before the server actually came up.
    Timer {
        id: ollamaStartupRetry
        interval: 700
        repeat: true
        property int attempts: 0
        onTriggered: {
            attempts += 1;
            root.refreshOllamaModels();
            if (root.ollamaReachable || attempts >= 8) {
                stop();
                attempts = 0;
                root.startingOllama = false;
            }
        }
        onRunningChanged: if (running) attempts = 0
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

    Component.onCompleted: {
        root.refreshOllamaModels();
        root.refreshClaudeAuth();
        root.refreshCodexAuth();
    }

    function isAvailable(providerId: string): bool {
        switch (providerId) {
        case "ollama": return root.ollamaAvailable;
        case "assistant": return root.assistantAvailable;
        case "claude": return root.claudeAvailable;
        case "codex": return root.codexAvailable;
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
            if (provider === "claude") {
                // Claude doesn't need a key at all (see claudeAvailable's
                // comment above) -- the generic "set an env var" message
                // below would be actively wrong here, since setting
                // ANTHROPIC_API_KEY does nothing for this provider.
                root.errorReceived(requestId, !root.claudeCliPresent ? qsTr("The claude CLI isn't installed.") : qsTr("Not logged in to Claude. Run `claude login` in a terminal, then refresh."));
            } else if (provider === "codex") {
                // Same reasoning as claude above -- see codexAvailable's
                // comment for why this is unverified.
                root.errorReceived(requestId, !root.codexCliPresent ? qsTr("The codex CLI isn't installed.") : qsTr("Not logged in to Codex. Run `codex login` in a terminal, then refresh."));
            } else {
                root.errorReceived(requestId, qsTr("No API key configured for %1. Set %2 to enable.").arg(label).arg(root.requiredEnvVar(provider)));
            }
            return;
        }

        root.busy = true;
        root.activeRequestId = requestId;

        switch (provider) {
        case "claude":
            claudeProc.command = ["claude", "-p", text, "--disallowed-tools", "*"];
            claudeProc.running = true;
            break;
        case "codex":
            // UNVERIFIED (see codexAvailable's comment): `codex exec` is a
            // good-faith guess at the CLI's real non-interactive
            // prompt-and-exit invocation, modeled on `claude -p`'s shape.
            // Needs a live test against the real binary before this is
            // trusted -- see docs/LEDGER.md.
            codexProc.command = ["codex", "exec", text];
            codexProc.running = true;
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

    // UNVERIFIED (see codexAvailable's comment): mirrors claudeProc's
    // StdioCollector pattern exactly, on the assumption `codex exec` behaves
    // like a plain prompt-and-exit CLI call the same way `claude -p` does.
    Process {
        id: codexProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.responseReceived(root.activeRequestId, text.trim());
                root._finish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0 && codexProc.exitCode !== 0)
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
