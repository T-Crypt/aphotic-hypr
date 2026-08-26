pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Wraps the llmfit CLI (github.com/AlexsJones/llmfit, `ai` profile layer) --
// a hardware-aware model recommendation tool, entirely separate from the
// AiProviders/AiConfig chat-provider registry. Button-triggered only (no
// polling): a hardware scan shells out to real detection every time, so
// running it on a timer would mean spawning nvidia-smi/rocm-smi etc.
// repeatedly for no reason.
Singleton {
    id: root

    property bool checked: false
    property bool available: false
    property bool scanning: false
    property string errorText: ""
    property var systemInfo: null
    property var recommendations: []

    // Best-effort guess at the model's Ollama library tag -- llmfit's
    // catalog is GGUF/HuggingFace-shaped (full model names, llama.cpp
    // quant strings) with no field mapping to Ollama's own registry
    // naming, so this is a heuristic, not a lookup. Callers must show the
    // guessed tag to the user before pulling it, never pull it silently.
    function guessOllamaTag(model: var): string {
        if (!model || !model.name)
            return "";
        let slug = model.name.toLowerCase().replace(/-instruct.*$/, "").replace(/-chat.*$/, "").replace(/-gguf.*$/i, "");
        const familyMatch = slug.match(/^([a-z0-9.]+?)[-_]?\d+(?:\.\d+)?b\b/);
        const family = familyMatch ? familyMatch[1] : slug.split(/[-_]/)[0];
        const sizeMatch = (model.parameter_count ?? "").match(/[\d.]+[bB]/);
        const size = sizeMatch ? sizeMatch[0].toLowerCase() : "";
        return size ? `${family}:${size}` : family;
    }

    function scan(): void {
        if (root.scanning || !root.available)
            return;
        root.scanning = true;
        root.errorText = "";
        scanProc.running = true;
    }

    Process {
        id: checkProc

        command: ["sh", "-c", "command -v llmfit"]
        onExited: {
            root.available = checkProc.exitCode === 0;
            root.checked = true;
        }
    }

    Process {
        id: scanProc

        command: ["llmfit", "recommend", "--json", "--limit", "3"]

        stdout: StdioCollector {
            id: scanStdout

            onStreamFinished: {
                root.scanning = false;
                if (scanProc.exitCode !== 0) {
                    root.errorText = scanStderr.text.trim() || qsTr("llmfit exited with code %1").arg(scanProc.exitCode);
                    root.recommendations = [];
                    root.systemInfo = null;
                    return;
                }
                try {
                    const data = JSON.parse(text);
                    root.systemInfo = data.system ?? null;
                    root.recommendations = data.models ?? [];
                    // llmfit can warn on stderr (e.g. a flaky nvidia-smi read)
                    // while still exiting 0 with usable JSON -- surfacing
                    // both rather than hiding the warning behind a clean exit
                    // code, since a warning here means the detected hardware
                    // itself may be wrong.
                    root.errorText = scanStderr.text.trim();
                } catch (e) {
                    root.errorText = qsTr("llmfit produced unexpected output: %1").arg(text.slice(0, 200));
                    root.recommendations = [];
                    root.systemInfo = null;
                }
            }
        }

        stderr: StdioCollector {
            id: scanStderr
        }
    }

    Component.onCompleted: checkProc.running = true
}
