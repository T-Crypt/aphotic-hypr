pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// Ollama's adapter onto BackendClaims. /api/ps reports each model's own
// size and size_vram, so the amounts are Ollama's measurement rather than
// an adopted PID: GpuVramSource skips Ollama's runner for that reason. A
// model with size_vram 0 is running in system RAM and claims memory only.
//
// Driven off the runningModels AiProviders hands in; AiProviders' /api/ps
// timer is the one clock.
BackendClaims {
    id: root

    property var runningModels: []
    property string host: ""

    owner: "ollama"
    label: qsTr("Ollama")
    models: (root.runningModels ?? []).map(m => ({
        name: m?.name ?? "",
        vramMiB: (m?.size_vram ?? 0) / (1024 * 1024),
        ramMiB: ((m?.size ?? 0) - (m?.size_vram ?? 0)) / (1024 * 1024)
    }))
    unload: name => {
        if (root.host)
            root._unloadProc.exec(["curl", "-s", "-m", "10", "-X", "POST", `${root.host}/api/generate`, "-d", JSON.stringify({ model: name, keep_alive: 0 })]);
    }

    property Process _unloadProc: Process {}
}
