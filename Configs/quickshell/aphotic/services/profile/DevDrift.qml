pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Environment drift for the open project (APHOTIC_UNIFIED_VISION.md
// §3.3): passive, informational, never acted on.
//
// Core, not a plugin, and hardcoded to InstallProfile.devEnabled -- this
// is the `dev` layer's own baseline, the same call GamingProfile went the
// other way on. It stays core specifically so the Dev notch tile and any
// later Dev surface read one answer instead of one plugin depending on
// another, which the layer model forbids outright.
//
// Not demand-gated the way AgentEvents is: there is no tail to hold open.
// A scan is one `stat` per project open and nothing runs between them.
//
// Deliberately narrow. A lockfile older than the manifest it locks is a
// fact readable from mtimes alone -- no project tooling is executed, no
// daemon is started, and nothing here can be wrong about a version it
// never parsed. Reading declared toolchain versions (mise, containers)
// means running the toolchain, which needs binaries no base install has.
Singleton {
    id: root

    readonly property bool enabled: InstallProfile.devEnabled

    // [{ manifest, lock }] -- the manifest is newer than the lockfile that
    // should have been regenerated from it.
    readonly property var findings: root._findings
    readonly property bool detected: root._findings.length > 0

    readonly property string summary: {
        if (root._findings.length === 0)
            return "";
        if (root._findings.length === 1)
            return qsTr("%1 is newer than %2").arg(root._findings[0].manifest).arg(root._findings[0].lock);
        return qsTr("%n lockfile(s) older than their manifest", "", root._findings.length);
    }

    readonly property var _pairs: [
        {
            manifest: "package.json",
            locks: ["package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb"]
        },
        {
            manifest: "Cargo.toml",
            locks: ["Cargo.lock"]
        },
        {
            manifest: "pyproject.toml",
            locks: ["poetry.lock", "uv.lock", "pdm.lock"]
        },
        {
            manifest: "go.mod",
            locks: ["go.sum"]
        },
        {
            manifest: "Gemfile",
            locks: ["Gemfile.lock"]
        },
        {
            manifest: "composer.json",
            locks: ["composer.lock"]
        }
    ]

    property var _findings: []
    property string _scanned: ""

    function _scan(path: string): void {
        root._findings = [];
        root._scanned = path;

        if (!root.enabled || path === "")
            return;

        const names = [];
        for (const pair of root._pairs) {
            names.push(pair.manifest);
            for (const lock of pair.locks)
                names.push(lock);
        }

        const base = path.replace(/\/+$/, "");
        // %n back, not just %Y: stat skips what does not exist, so the
        // reply is only aligned with the request if each line names itself.
        statProc.command = ["stat", "-c", "%n %Y", "--"].concat(names.map(n => `${base}/${n}`));
        statProc.running = true;
    }

    function _apply(text: string): void {
        const mtimes = {};
        for (const line of text.split("\n")) {
            const cut = line.lastIndexOf(" ");
            if (cut < 0)
                continue;
            const epoch = parseInt(line.slice(cut + 1), 10);
            if (!isNaN(epoch))
                mtimes[line.slice(0, cut).split("/").pop()] = epoch;
        }

        const found = [];
        for (const pair of root._pairs) {
            const manifest = mtimes[pair.manifest];
            if (manifest === undefined)
                continue;

            // A manifest with no lockfile at all is an unbuilt project, not
            // drift -- reporting it would badge the notch on every fresh
            // clone.
            let newest = -1;
            let newestName = "";
            for (const lock of pair.locks) {
                if (mtimes[lock] !== undefined && mtimes[lock] > newest) {
                    newest = mtimes[lock];
                    newestName = lock;
                }
            }
            if (newest >= 0 && manifest > newest)
                found.push({
                    manifest: pair.manifest,
                    lock: newestName
                });
        }
        root._findings = found;
    }

    onEnabledChanged: root._scan(root.enabled ? DevProfile.activeProjectPath : "")

    Connections {
        target: DevProfile

        function onActiveProjectPathChanged(): void {
            root._scan(DevProfile.activeProjectPath);
        }
    }

    Process {
        id: statProc

        // Missing paths make stat exit non-zero after printing every path
        // that did exist, so stdout is read regardless of exit status.
        stdout: StdioCollector {
            onStreamFinished: root._apply(text)
        }
    }
}
