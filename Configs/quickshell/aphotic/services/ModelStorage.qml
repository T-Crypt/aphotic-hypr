pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Directory upkeep for the two places local model weights actually land on
// disk: Ollama's own store (it manages this itself -- we only surface path
// + usage here, never touch its internal blob/manifest layout, which is
// undocumented and version-fragile) and a user-chosen GGUF directory (fully
// ours to manage: create it, list what's in it, delete individual files).
Singleton {
    id: root

    readonly property string ollamaDir: {
        const override = Quickshell.env("OLLAMA_MODELS");
        return override && override.length > 0 ? override : `${Quickshell.env("HOME")}/.ollama/models`;
    }
    readonly property string ggufDir: Settings.ggufModelsDir

    property bool ollamaDirExists: false
    property string ollamaDirSize: ""

    property bool ggufDirExists: false
    property string ggufDirSize: ""
    property var ggufFiles: []

    function formatBytes(bytes: real): string {
        if (bytes >= 1073741824)
            return qsTr("%1 GB").arg((bytes / 1073741824).toFixed(1));
        if (bytes >= 1048576)
            return qsTr("%1 MB").arg((bytes / 1048576).toFixed(1));
        return qsTr("%1 KB").arg((bytes / 1024).toFixed(1));
    }

    function refreshOllama(): void {
        ollamaCheckProc.command = ["sh", "-c", `[ -d '${root.ollamaDir}' ] && du -sh '${root.ollamaDir}' 2>/dev/null | cut -f1 || echo MISSING`];
        ollamaCheckProc.running = true;
    }

    function refreshGguf(): void {
        ggufCheckProc.command = ["sh", "-c", `[ -d '${root.ggufDir}' ] && (du -sh '${root.ggufDir}' 2>/dev/null | cut -f1; find '${root.ggufDir}' -maxdepth 1 -name '*.gguf' -printf '%s %f\\n') || echo MISSING`];
        ggufCheckProc.running = true;
    }

    function createOllamaDir(): void {
        mkdirOllamaProc.exec(["mkdir", "-p", root.ollamaDir]);
    }

    function createGgufDir(): void {
        mkdirGgufProc.exec(["mkdir", "-p", root.ggufDir]);
    }

    function deleteGgufFile(name: string): void {
        if (!name || name.includes("/"))
            return;
        deleteGgufProc.exec(["rm", "-f", `${root.ggufDir}/${name}`]);
    }

    Process {
        id: ollamaCheckProc
        stdout: StdioCollector {
            onStreamFinished: {
                const trimmed = text.trim();
                if (trimmed === "MISSING" || trimmed.length === 0) {
                    root.ollamaDirExists = false;
                    root.ollamaDirSize = "";
                } else {
                    root.ollamaDirExists = true;
                    root.ollamaDirSize = trimmed;
                }
            }
        }
    }

    Process {
        id: ggufCheckProc
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").map(l => l.trim()).filter(l => l.length > 0);
                if (lines.length === 0 || lines[0] === "MISSING") {
                    root.ggufDirExists = false;
                    root.ggufDirSize = "";
                    root.ggufFiles = [];
                    return;
                }
                root.ggufDirExists = true;
                root.ggufDirSize = lines[0];
                root.ggufFiles = lines.slice(1).map(line => {
                    const spaceIdx = line.indexOf(" ");
                    const size = parseInt(line.slice(0, spaceIdx), 10);
                    const name = line.slice(spaceIdx + 1);
                    return { name, sizeBytes: size, sizeText: root.formatBytes(size) };
                });
            }
        }
    }

    Process {
        id: mkdirOllamaProc
        onExited: root.refreshOllama()
    }

    Process {
        id: mkdirGgufProc
        onExited: root.refreshGguf()
    }

    Process {
        id: deleteGgufProc
        onExited: root.refreshGguf()
    }

    Connections {
        target: Settings
        function onGgufModelsDirChanged() {
            root.refreshGguf();
        }
    }

    Component.onCompleted: {
        root.refreshOllama();
        root.refreshGguf();
    }
}
