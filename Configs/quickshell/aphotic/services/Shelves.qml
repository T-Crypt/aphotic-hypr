pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services
import "ShelfPolicy.js" as Policy

Singleton {
    id: root
    property var screenStates: []
    property var screens: Quickshell.screens
    readonly property var outputNames: root.screens.map(s => s.name)
    readonly property bool blocked: Surfaces.suppressed || SessionLockState.locked
    readonly property var openEdges: root._open
    property var _open: []
    property var _tracked: ({})
    property var selectedTabs: ({})

    function config(output: string): var { return Policy.config(Settings.shelfOutputs, output); }
    function update(output: string, edge: string, patch: var): bool {
        const screen = root.screens.find(s => s.name === output);
        const next = Policy.update(Settings.shelfOutputs, output, edge, patch, screen?.description);
        if (!next) return false;
        Settings.shelfOutputs = next;
        return true;
    }
    function stateFor(output: string): var { return Array.from(root.screenStates).find(s => s.modelData?.name === output) ?? null; }
    function isOpen(output: string, edge: string): bool { return root._open.includes(Policy.key(output,edge)); }
    function name(output: string, edge: string): string { return "shelf:" + output + ":" + edge; }
    function toggle(output: string, edge: string): bool {
        if (!Policy.validEdge(edge)) return false;
        if (root.isOpen(output,edge)) { root.closeEdge(output,edge); return true; }
        if (root.blocked || !root.outputNames.includes(output) || !root.config(output)[edge].enabled || !root.stateFor(output)) return false;
        const n = root.name(output,edge), state = root.stateFor(output);
        Surfaces.declare(n,"shelf");
        root._tracked = Object.assign({},root._tracked,{[Policy.key(output,edge)]:state});
        root._open = root._open.concat([Policy.key(output,edge)]);
        Surfaces.track(state,n,true);
        return true;
    }
    function closeEdge(output: string, edge: string): void {
        const k = Policy.key(output,edge), state = root._tracked[k];
        root._open = root._open.filter(v => v !== k);
        if (state) Surfaces.track(state,root.name(output,edge),false);
        Surfaces.undeclare(root.name(output,edge));
        const next = Object.assign({},root._tracked); delete next[k]; root._tracked = next;
        const tabs = Object.assign({},root.selectedTabs); delete tabs[k]; root.selectedTabs = tabs;
    }
    function close(output: string): void { root.closeEdge(output,"left"); root.closeEdge(output,"right"); }
    function openTab(output: string, edge: string, id: string): bool {
        // Task 5 supplies the tab registry and hosted content.
        return false;
    }
    function reconcile(): void {
        const keep = root.blocked ? [] : Policy.reconcile(root._open,Settings.shelfOutputs,root.outputNames.filter(n => root.stateFor(n) !== null));
        for (const k of root._open.slice()) {
            if (!keep.includes(k)) { const at=k.lastIndexOf('/'); root.closeEdge(k.slice(0,at),k.slice(at+1)); }
        }
    }
    onOutputNamesChanged: root.reconcile()
    onBlockedChanged: root.reconcile()
    onScreenStatesChanged: root.reconcile()
    Connections { target: Settings; function onShelfOutputsChanged(): void { root.reconcile(); } }
    Connections {
        target: Surfaces
        function onCloseRequested(state: var, name: string): void {
            for (const edge of ["left","right"])
                if (name === root.name(state?.modelData?.name,edge)) root.closeEdge(state.modelData.name,edge);
        }
    }
}
