import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.notch
import qs.services
import qs.services.profile

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
            return `tile=${w.notch.tileId}`;
        }

        function collapse(): string {
            const w = windows.instances[0];
            w.notch.collapse();
            return `tile=${w.notch.tileId}`;
        }

        function pick(t: string): string {
            const w = windows.instances[0];
            w.notch.tileId = t;
            return `tile=${w.notch.tileId}`;
        }

        function dock(edge: string): string {
            Settings.barHorizontal = edge === "top" || edge === "bottom";
            Settings.barPositionBottom = edge === "bottom";
            Settings.barPositionRight = edge === "right";
            return `horizontal=${Settings.barHorizontal} bottom=${Settings.barPositionBottom} right=${Settings.barPositionRight}`;
        }

        function tabs(): string {
            const n = windows.instances[0].notch;
            return JSON.stringify({
                layers: InstallProfile.layers,
                known: InstallProfile.known,
                tiles: n.tiles.map(t => t.label),
                switchable: n.switchable
            });
        }

        function state(): string {
            const w = windows.instances[0];
            return JSON.stringify({
                tile: w.notch.tileId,
                shownTile: w.notch.shownTileId,
                dockHorizontal: w.notch.dockHorizontal,
                growsPositive: w.notch.growsPositive,
                openProgress: w.notch.openProgress.toFixed(3),
                panelHeight: Math.round(w.notch.panelHeight),
                notchW: Math.round(w.notch.width),
                notchH: Math.round(w.notch.height),
                winW: w.width,
                winH: w.height,
                sampling: ProcessUsage.sampling,
                primed: ProcessUsage.primed,
                sortBy: ProcessUsage.sortBy,
                gpuPerc: Math.round(SystemUsage.gpuPerc * 100),
                gpuStats: SystemUsage.gpuStatsAvailable,
                fastMon: SystemUsage.fastMonitoring,
                gpuSupported: ProcessUsage.gpuSupported,
                gpuAvailable: ProcessUsage.gpuAvailable,
                top: ProcessUsage.processes.slice(0, 6).map(p => `${p.name} cpu=${p.cpu.toFixed(1)}% rss=${Math.round(p.rssKib / 1024)}M vram=${p.gpuMib ?? "-"}`)
            });
        }

        function dev(): string {
            return JSON.stringify({
                enabled: DevProfile.enabled,
                active: DevProfile.active,
                name: DevProfile.activeProjectName,
                path: DevProfile.activeProjectPath,
                phase: ProfileEngine.phaseOf("dev"),
                registered: Object.keys(ProfileEngine.profiles),
                snapshotParts: ProfileEngine.profiles["dev"]?.snapshot ?? null,
                captured: StateSnapshot.capturedIds,
                capturedParts: StateSnapshot.snapshots["dev"]?.parts ?? null,
                capturedKeys: Object.keys(StateSnapshot.snapshots["dev"] ?? ({})),
                devClaims: ResourceEngine.claimsOf("dev"),
                tiles: windows.instances[0].notch.tiles.map(t => t.label)
            });
        }

        function open(path: string): string {
            DevProfile.projectOpened(path);
            return `${DevProfile.activeProjectName} / ${ProfileEngine.phaseOf("dev")}`;
        }

        function sort(key: string): string {
            ProcessUsage.sortBy = key;
            return key;
        }
    }
}
