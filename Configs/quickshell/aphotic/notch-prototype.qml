import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.notch
import qs.services

// Isolated entry point for the notch prototype -- `qs -p
// Configs/quickshell/aphotic/notch-prototype.qml` brings up the notch and
// nothing else, so its behaviour can be driven and its log read without a
// second full shell fighting the running one for the desktop. Not part of
// shell.qml; delete with the branch.
ShellRoot {
    id: root

    Variants {
        id: windows
        model: Quickshell.screens

        NotchWindow {}
    }

    IpcHandler {
        target: "notchtest"

        function cycle(): string {
            const w = windows.instances[0];
            w.notch.cycle();
            return `tile=${w.notch.tile}`;
        }

        function collapse(): string {
            const w = windows.instances[0];
            w.notch.collapse();
            return `tile=${w.notch.tile}`;
        }

        function pick(t: int): string {
            const w = windows.instances[0];
            w.notch.tile = t;
            return `tile=${w.notch.tile}`;
        }

        function state(): string {
            const w = windows.instances[0];
            return JSON.stringify({
                tile: w.notch.tile,
                shownTile: w.notch.shownTile,
                notchW: Math.round(w.notch.width),
                notchH: Math.round(w.notch.height),
                winW: w.width,
                winH: w.height,
                sampling: ProcessUsage.sampling,
                primed: ProcessUsage.primed,
                sortBy: ProcessUsage.sortBy,
                gpuSupported: ProcessUsage.gpuSupported,
                gpuAvailable: ProcessUsage.gpuAvailable,
                top: ProcessUsage.processes.slice(0, 6).map(p => `${p.name} cpu=${p.cpu.toFixed(1)}% rss=${Math.round(p.rssKib / 1024)}M vram=${p.gpuMib ?? "-"}`)
            });
        }

        function sort(key: string): string {
            ProcessUsage.sortBy = key;
            return key;
        }
    }
}
