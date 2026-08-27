pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Arch/AUR-only. `helper` resolves to "yay"/"paru"/"" (Component.onCompleted
// probe below) -- `available` gates both the bar/IPC toggle and the search
// itself, so this is silently absent rather than erroring on a non-Arch
// or helper-less machine.
//
// Debounced, self-correcting search loop: a keystroke restarts `debounce`
// rather than firing a Process directly (yay -Ss round-trips the AUR RPC,
// too slow to run on every keystroke). When the timer fires, if a search
// is already running, `_maybeSearch` just returns -- `searchProc.onExited`
// re-checks whether `query` has changed since the last dispatched search
// and restarts if so, instead of killing/reassigning an in-flight Process.
Singleton {
    id: root

    property string helper: ""
    readonly property bool available: root.helper.length > 0

    property string query: ""
    property var results: []
    property bool searching: false
    property string errorText: ""

    property string _lastSearchedQuery: ""

    function setQuery(q: string): void {
        root.query = q;
        debounce.restart();
    }

    Timer {
        id: debounce
        interval: 280
        onTriggered: root._maybeSearch()
    }

    function _maybeSearch(): void {
        if (!root.available) {
            root.results = [];
            return;
        }
        const q = root.query.trim();
        if (q.length < 2) {
            root.results = [];
            root._lastSearchedQuery = "";
            root.errorText = "";
            return;
        }
        if (searchProc.running)
            return;
        if (q === root._lastSearchedQuery)
            return;
        root._lastSearchedQuery = q;
        root.searching = true;
        root.errorText = "";
        searchProc.command = [root.helper, "--color=never", "-Ss", q];
        searchProc.running = true;
    }

    function _parseResults(output: string): var {
        const lines = output.split("\n");
        const out = [];
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.length === 0 || /^[ \t]/.test(line))
                continue;
            const slash = line.indexOf("/");
            if (slash === -1)
                continue;
            const repo = line.slice(0, slash);
            const rest = line.slice(slash + 1);
            const nameEnd = rest.indexOf(" ");
            const name = nameEnd === -1 ? rest : rest.slice(0, nameEnd);
            const installed = line.includes("(Installed");
            const desc = i + 1 < lines.length && /^[ \t]/.test(lines[i + 1]) ? lines[i + 1].trim() : "";
            out.push({
                name,
                repo,
                isAur: repo === "aur",
                installed,
                description: desc
            });
        }
        return out;
    }

    Process {
        id: searchProc

        stdout: StdioCollector {
            onStreamFinished: {
                root.results = root._parseResults(text);
                root.searching = false;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0 && root.results.length === 0)
                    root.errorText = text.trim().split("\n")[0];
            }
        }
        onExited: root._maybeSearch()
    }

    // Fires the install in a real tiled kitty window, not a layer-shell
    // overlay -- yay may need to prompt (confirmation, sudo password,
    // a provider pick among multiple AUR candidates), and only a normal
    // window gives that its usual alt-tab/focus semantics. No custom QML
    // progress UI parsing yay's output; the terminal IS the progress UI.
    // Completion is reported by the launched script calling notify-send
    // itself (not by watching the kitty process's own exit code -- kitty
    // was confirmed live on this machine to always exit 0 regardless of
    // the child command's real status), which lands in the real Notifs
    // pipeline and therefore in Notification History for free.
    function install(pkg: string): void {
        if (!root.available || pkg.trim().length === 0)
            return;
        Quickshell.execDetached(["notify-send", "-a", "aphotic", qsTr("Installing %1…").arg(pkg)]);
        const script = `${root.helper} -S "$1"; ec=$?; if [ "$ec" -eq 0 ]; then notify-send -a aphotic "$1 installed"; else notify-send -a aphotic "$1 install failed (exit $ec)"; fi; echo; echo "Press any key to close…"; read -k 1 -s; exit "$ec"`;
        Quickshell.execDetached(["kitty", "zsh", "-c", script, "_", pkg]);
    }

    Process {
        id: helperDetectProc
        command: ["sh", "-c", "command -v yay || command -v paru"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim().split("\n")[0] ?? "";
                root.helper = path.length === 0 ? "" : path.endsWith("paru") ? "paru" : "yay";
            }
        }
    }

    Component.onCompleted: helperDetectProc.running = true
}
