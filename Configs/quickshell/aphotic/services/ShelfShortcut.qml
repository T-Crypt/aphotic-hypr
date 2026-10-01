pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "ShelfPolicy.js" as Policy
Scope {
    id: root
    required property string edge
    readonly property bool wanted: Shelves.outputNames.some(n => Shelves.config(n)[root.edge].enabled)
    readonly property string form: Hypr.usingLua ? "lua" : "legacy"
    readonly property string symbol: root.edge === "left" ? "bracketleft" : "bracketright"
    readonly property string combo: "SUPER + " + root.symbol
    readonly property string legacyCombo: "SUPER, " + root.symbol
    property string applied: ""
    property string reason: ""
    property bool busy: false
    property bool pending: false
    property bool exited: false
    property bool collected: false
    property int exitCode: -1
    property string operation: ""
    function args(form: string, bind: bool): var {
        if (form === "lua") return ["hyprctl","eval",bind
            ? `hl.bind("${root.combo}", hl.dsp.exec_cmd("${Policy.command(root.edge)}"), { description = "Toggle ${root.edge} shelf" })`
            : `hl.unbind("${root.combo}")`];
        return ["hyprctl","keyword",bind ? "bindd" : "unbind",bind
            ? `${root.legacyCombo}, Toggle ${root.edge} shelf, exec, ${Policy.command(root.edge)}` : root.legacyCombo];
    }
    function refresh(): void {
        if (root.busy) { root.pending = true; return; }
        if (!root.wanted && !root.applied) { root.reason = ""; return; }
        root.busy = true; root.pending = false; root.exited = false; root.collected = false;
        check.running = true;
    }
    function finish(): void {
        root.busy = false;
        if (root.pending) { root.pending = false; Qt.callLater(root.refresh); }
    }
    function checked(): void {
        if (!root.exited || !root.collected) return;
        let binds;
        try { binds = JSON.parse(output.text); } catch(e) { binds = null; }
        if (root.exitCode !== 0 || !Array.isArray(binds)) {
            root.reason = qsTr("Shortcut check unavailable; use IPC"); root.finish(); return;
        }
        if (Policy.conflict(binds,root.edge)) {
            root.applied = "";
            root.reason = qsTr("Shortcut already bound; use IPC"); root.finish(); return;
        }
        root.reason = "";
        const own = binds.some(b => b.dispatcher === "exec" && b.arg === Policy.command(root.edge)
            && !b.mouse && b.key === root.symbol && (b.modmask & 255) === 64);
        if (!root.wanted && !own) { root.applied = ""; root.finish(); return; }
        if (root.wanted && own && root.applied === root.form) { root.finish(); return; }
        root.operation = root.wanted ? root.form : "";
        binder.command = root.args(root.operation || root.applied || root.form,root.wanted);
        binder.running = true;
    }
    onWantedChanged: root.refresh()
    onFormChanged: root.refresh()
    Component.onCompleted: root.refresh()
    Connections { target: Hypr; function onConfigReloaded(): void { root.refresh(); } }
    Connections { target: HyprKeybinds; function onEntriesChanged(): void { root.refresh(); } }
    Component.onDestruction: {
        // Inspect ownership again rather than unbinding a replacement user shortcut.
        if (root.applied) Quickshell.execDetached(["python3","-c",
            "import json,subprocess,sys; b=json.loads(subprocess.check_output(['hyprctl','-j','binds'])); own=[x for x in b if x.get('key')==sys.argv[1] and (x.get('modmask',0)&255)==64 and not x.get('mouse')]; subprocess.run(sys.argv[3:]) if own and all(x.get('dispatcher')=='exec' and x.get('arg')==sys.argv[2] for x in own) else None",
            root.symbol,Policy.command(root.edge)].concat(root.args(root.applied,false)));
    }
    Process {
        id: check
        command: ["hyprctl","-j","binds"]
        stdout: StdioCollector { id: output; onStreamFinished: { root.collected = true; root.checked(); } }
        onExited: (code,status) => { root.exitCode=code; root.exited=true; root.checked(); }
    }
    Process {
        id: binder
        onExited: (code,status) => {
            if (code === 0) root.applied = root.operation;
            else root.reason = qsTr("Shortcut registration failed; use IPC");
            root.finish();
        }
    }
}
