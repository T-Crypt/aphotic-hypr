pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.ai

// Uniform interface over the four AI Chat providers. Claude is the only
// claude-CLI-subprocess-based provider; Ollama/Gemini/ChatGPT are direct
// HTTP clients via curl -- see docs/COMMAND_CENTER.md §4 for why (Ollama
// has no Anthropic-Messages-API-shaped endpoint, verified live).
Singleton {
    id: root

    readonly property var _baseProviders: [
        { id: "ollama", label: "Ollama", requiresApiKey: false },
        // Claude is deliberately here despite being a harness: it is both,
        // and AgentRoles.qml carries that as an explicit `chat` flag rather
        // than this list quietly disagreeing with the role classifier.
        // Codex used to sit alongside it and does not belong -- it is a
        // harness with no plain conversational mode, so servesChat() filters
        // it out below (APHOTIC_UNIFIED_VISION.md §4.1).
        { id: "claude", label: "Claude", requiresApiKey: false },
        { id: "codex", label: "Codex", requiresApiKey: false },
        { id: "gemini", label: "Gemini", requiresApiKey: true },
        { id: "chatgpt", label: "ChatGPT", requiresApiKey: true }
    ]
    // Pinned to the top of the list, and only present at all, once
    // installed -- there's no "not installed yet" pill to click; install.sh
    // is the only install path (NVIDIA-gated, opt-in), see AiConfig.qml.
    // Three independent filters, deliberately not merged:
    //   - servesChat drops harnesses with no conversational mode (Codex).
    //   - isEnabled drops anything an [agents.*] table turned off, which is
    //     how the opt-in-only backends stay absent until asked for.
    //   - the layer check drops every locally-hosted backend, keyed off
    //     AgentRoles' own `locality` rather than a hardcoded id, so this
    //     stays right as local providers are added. Claude, Gemini and
    //     ChatGPT have no locality: they are a CLI session and two raw HTTP
    //     APIs, none installed by the `ai` layer, so a base shell still
    //     chats with all three.
    //
    // A local backend therefore needs BOTH the layer and its own opt-in --
    // an [agents.unsloth] flag on a shell with no `ai` layer stays inert,
    // because the layer is what would have installed anything to talk to.
    readonly property var _chatProviders: root._baseProviders.filter(p => AgentRoles.servesChat(p.id) && AgentRoles.isEnabled(p.id) && (AgentRoles.localityFor(p.id) !== "local" || InstallProfile.aiEnabled))
    // Layer-gated as well as install-gated: the Assistant is a local model
    // served through Ollama, so turning the `ai` layer off has to take it
    // with everything else locally-hosted, even on a machine where
    // assistant.sh had already pulled the weights.
    readonly property var _coreProviders: InstallProfile.aiEnabled && AiConfig.assistantEnabled ? [{ id: "assistant", label: "Aphotic Assistant", requiresApiKey: false }].concat(root._chatProviders) : root._chatProviders

    // Plugin-contributed pills (the `chat-provider` capability), ahead of
    // the core list because a provider someone installed on purpose is the
    // one they mean. PluginRegistry has already applied each one's gate,
    // so anything reaching here is installed, enabled and unlocked; a
    // backend this shell does not speak is dropped, same fail-closed rule
    // as an unrecognised gate token.
    readonly property var _pluginProviders: PluginRegistry.chatProviderRegistrations
        .filter(p => root._backendSpeaks(p.backend))
        .map(p => ({ id: p.id, label: p.label, requiresApiKey: false, backend: p.backend, plugin: p.plugin }))

    // The one list every chat surface reads. Plugin providers are part of
    // it rather than a second list beside it -- two lists would mean every
    // consumer choosing which one it meant, and choosing wrong somewhere.
    readonly property var providers: root._pluginProviders.concat(root._coreProviders)

    function _backendSpeaks(backend: string): bool {
        return backend === "ollama";
    }

    function pluginProviderFor(id: string): var {
        return root._pluginProviders.find(p => p.id === id) ?? null;
    }

    // {model, systemPrompt} per plugin provider id, read from the state
    // file each plugin writes. Kept as one object reassigned wholesale --
    // mutating it in place would leave every binding on it stale.
    property var pluginProviderState: ({})

    function _setPluginProviderState(id: string, raw: string): void {
        const next = Object.assign({}, root.pluginProviderState);
        if (raw.length === 0) {
            delete next[id];
        } else {
            try {
                const data = JSON.parse(raw);
                next[id] = { model: data.model ?? "", systemPrompt: data.systemPrompt ?? "" };
            } catch (e) {
                delete next[id];
            }
        }
        root.pluginProviderState = next;
    }

    Instantiator {
        model: PluginRegistry.chatProviderRegistrations

        delegate: FileView {
            required property var modelData

            path: modelData.statePath
            watchChanges: true
            onLoaded: root._setPluginProviderState(modelData.id, text())
            onLoadFailed: error => root._setPluginProviderState(modelData.id, "")
        }
    }

    // A provider id saved before it stopped being offered (or one an
    // [agents.*] override has since turned off) must not leave the chat
    // surfaces pointing at a pill that no longer exists -- every entry
    // point resolves its stored selection through this.
    function chatProviderOr(id: string): string {
        if (root.providers.some(p => p.id === id))
            return id;
        return root.providers[0]?.id ?? "ollama";
    }

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
    property bool stoppingOllama: false

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

    function stopOllama(): void {
        if (root.stoppingOllama || !root.ollamaReachable)
            return;
        root.stoppingOllama = true;
        ollamaStopProc.exec(["sh", "-c", "pkill -x ollama"]);
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
                if (!root.ollamaReachable)
                    Toaster.toast(qsTr("Couldn't start Ollama"), qsTr("Not reachable at %1 after starting -- check the ollama binary is installed").arg(AiConfig.ollamaHost), "error");
                attempts = 0;
                root.startingOllama = false;
            }
        }
        onRunningChanged: if (running) attempts = 0
    }

    Process {
        id: ollamaStopProc
        onExited: exitCode => {
            if (exitCode === 127) {
                root.stoppingOllama = false;
                Toaster.toast(qsTr("Couldn't stop Ollama"), qsTr("pkill isn't available on this system"), "error");
                return;
            }
            ollamaStopRetry.restart();
        }
    }

    Timer {
        id: ollamaStopRetry
        interval: 500
        repeat: true
        property int attempts: 0
        onTriggered: {
            attempts += 1;
            root.refreshOllamaModels();
            if (!root.ollamaReachable || attempts >= 6) {
                stop();
                if (root.ollamaReachable)
                    Toaster.toast(qsTr("Couldn't stop Ollama"), qsTr("Still reachable at %1 -- it may be running as the system service (sudo systemctl stop ollama)").arg(AiConfig.ollamaHost), "error");
                attempts = 0;
                root.stoppingOllama = false;
            }
        }
        onRunningChanged: if (running) attempts = 0
    }

    // GET /api/ps -- currently-loaded (in-VRAM) models, separate from the
    // full installed-models list above.
    Process {
        id: ollamaPsProc
        // Unlike ollamaModels (kept stale on purpose above), a resident-in-
        // VRAM list read from a host that answered nothing is definitionally
        // wrong -- nothing is loaded if the server is gone. Clearing on a
        // hard curl failure is what lets OllamaClaims' claims drop when
        // Ollama stops, instead of the claim table carrying a model that
        // no longer exists.
        onExited: exitCode => {
            root.ollamaReachable = exitCode === 0;
            if (exitCode !== 0)
                root.ollamaRunningModels = [];
        }
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

    // Ollama's VRAM footprint has to be tracked whether or not Settings is
    // open: Settings -> AI's own 5s timer only runs while that pane is
    // visible, and the Resource Engine claims below have to keep matching
    // reality when nothing is on screen. Ollama publishes no model
    // load/unload event, so polling /api/ps is the only source there is.
    // Backs off to 30s while the host isn't answering so a machine with no
    // Ollama running isn't paying for a curl every five seconds, and holds
    // off entirely mid-start/stop so it can't fight those retry timers over
    // ollamaReachable.
    Timer {
        id: ollamaPsPoll
        interval: root.ollamaReachable ? 5000 : 30000
        repeat: true
        triggeredOnStart: true
        running: InstallProfile.aiEnabled && AiConfig.ollamaHostConfigured && !root.startingOllama && !root.stoppingOllama
        onTriggered: root.refreshRunningModels()
    }

    OllamaClaims {
        runningModels: root.ollamaRunningModels
        host: AiConfig.ollamaHost
        enabled: InstallProfile.aiEnabled && AiConfig.ollamaHostConfigured
    }

    // Gated on the same install-time signal AgentProviders.qml's presence
    // poll already uses -- without the `ai` layer, `claude`/`codex` aren't
    // installed and probing for them on every shell start just produces
    // "Process failed to start" log noise (see issue #43). Ollama is
    // included too since it ships with the same layer; refreshOllamaModels()
    // stays callable on demand (Settings -> AI's refresh action, the
    // ollamaHostChanged handler above) for anyone pointing at a host that
    // wasn't set up through this layer at all.
    Component.onCompleted: {
        if (InstallProfile.aiEnabled) {
            root.refreshOllamaModels();
            root.refreshClaudeAuth();
            root.refreshCodexAuth();
        }
    }

    function isAvailable(providerId: string): bool {
        const plugin = root.pluginProviderFor(providerId);
        if (plugin) {
            // A pulled model is what makes the provider answerable, so an
            // installed plugin that has not finished its own setup reads as
            // unavailable rather than as a pill that errors on first send.
            if ((root.pluginProviderState[providerId]?.model ?? "").length === 0)
                return false;
            return plugin.backend === "ollama" ? root.ollamaAvailable : false;
        }
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

    // Why a provider is unavailable, in the user's words. One answer, because
    // there were two call sites guessing separately and the fallback both fell
    // back to -- "set an API key" -- is wrong for every provider that does not
    // use one. That already misfired: an Assistant whose Ollama host was unset
    // was told to set an API key, naming an empty env var, because the guess
    // keyed off "not claude" rather than off what the provider actually needs.
    function unavailableReason(providerId: string): string {
        const label = root.providers.find(p => p.id === providerId)?.label ?? providerId;

        const plugin = root.pluginProviderFor(providerId);
        if (plugin) {
            if ((root.pluginProviderState[providerId]?.model ?? "").length === 0)
                return qsTr("%1 hasn't finished setting up — no model is configured for it yet.").arg(label);
            return qsTr("No Ollama host configured. Set it in the model pill, or set OLLAMA_BASE_URL, to enable.");
        }

        switch (providerId) {
        case "claude":
            return !root.claudeCliPresent ? qsTr("The claude CLI isn't installed.") : qsTr("Not logged in to Claude. Run `claude login` in a terminal, then refresh.");
        case "codex":
            return !root.codexCliPresent ? qsTr("The codex CLI isn't installed.") : qsTr("Not logged in to Codex. Run `codex login` in a terminal, then refresh.");
        case "ollama":
        case "assistant":
            return qsTr("No Ollama host configured. Set it in the model pill, or set OLLAMA_BASE_URL, to enable.");
        }

        const envVar = root.requiredEnvVar(providerId);
        if (envVar.length === 0)
            return qsTr("%1 isn't available on this machine.").arg(label);
        return qsTr("No API key configured for %1. Set %2 to enable.").arg(label).arg(envVar);
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

        if ((provider === "ollama" || provider === "assistant" || root.pluginProviderFor(provider)?.backend === "ollama") && !AiConfig.ollamaHostConfigured) {
            root.errorReceived(requestId, qsTr("No Ollama host configured. Set it in the model pill, or set OLLAMA_BASE_URL, to enable."));
            return;
        }
        if (!root.isAvailable(provider)) {
            root.errorReceived(requestId, root.unavailableReason(provider));
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
            // Three shapes share this one Ollama call: plain Ollama, the
            // core Assistant, and any plugin provider on the ollama
            // backend. All a persona amounts to is a pinned model plus a
            // fixed system prompt, which is why a plugin can contribute one
            // without shipping a transport.
            const pluginState = root.pluginProviderState[provider];
            const isAssistant = provider === "assistant";
            const resolvedModel = pluginState ? pluginState.model : (isAssistant ? AiConfig.assistantModel : (model || AiConfig.ollamaModel));
            const systemPrompt = pluginState ? pluginState.systemPrompt : (isAssistant ? root.assistantSystemPrompt : "");
            const messages = systemPrompt.length > 0 ? [{ role: "system", content: systemPrompt }, { role: "user", content: text }] : [{ role: "user", content: text }];
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
