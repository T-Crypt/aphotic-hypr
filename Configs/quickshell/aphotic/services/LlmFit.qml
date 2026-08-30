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
    // Real bug found and fixed here (2026-08-29): this used to GUESS an
    // Ollama tag from the model's raw name/param-count via regex,
    // regardless of whether the model was actually published to Ollama's
    // registry under that guessed name. llmfit's recommendation pool is
    // dominated by community fine-tunes in vLLM/AWQ/GPTQ quantized
    // formats -- confirmed live, every field-tested recommendation on a
    // 24GB-VRAM RTX 4090 had `ollama_name: null` -- so the guess produced
    // plausible-looking but nonexistent tags (e.g.
    // `louismuk/gemma:26.6b`), and the one-click pull button below would
    // fail near-instantly against a tag that was never real. Fixed: only
    // return a tag llmfit itself confirms is real (`model.ollama_name`);
    // return "" otherwise, which the pull button's own
    // `visible: recRow.tag.length > 0` already correctly hides instead of
    // offering a pull that was always going to fail. Mirrors
    // lib/install/assistant.sh's resolve_assistant_model_via_llmfit() --
    // keep the two in sync if this changes.
    function guessOllamaTag(model: var): string {
        return model?.ollama_name ?? "";
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
        // Real bug (2026-08-29): reading checkProc.exitCode as a plain
        // property from inside a no-argument onExited handler returns
        // undefined here -- the property isn't populated by the time this
        // signal fires, a real Quickshell Process timing quirk (every
        // other correct onExited handler in this codebase, e.g.
        // AiProviders.qml's claudeAuthProc, captures the
        // exit code as the signal's own argument instead). That made
        // `checkProc.exitCode === 0` always false, so the Hardware
        // Advisor permanently reported llmfit as not installed even when
        // it genuinely was. Fixed by using the signal argument.
        onExited: exitCode => {
            root.available = exitCode === 0;
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
