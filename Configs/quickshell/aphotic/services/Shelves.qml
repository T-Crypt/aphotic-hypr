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
    // Tab acknowledgement counters, per edge. Deliberately not persisted:
    // a trace belongs to the panel that just became ready, so a restart
    // starts silent rather than tracing every remembered tab.
    property var _acks: ({})
    signal acksChanged()

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
        // The saved selection stays on the output; the live one does not,
        // so reopening a shelf restores the tab the user last chose there
        // without a closed shelf holding content.
        const tabs = Object.assign({},root.selectedTabs); delete tabs[k]; root.selectedTabs = tabs;
    }
    function close(output: string): void { root.closeEdge(output,"left"); root.closeEdge(output,"right"); }
    // A tab is only ever reachable through the registry: an id that does
    // not resolve for this edge, or that belongs to another edge, fails
    // closed here rather than leaving a loader pointed at nothing.
    function openTab(output: string, edge: string, id: string): bool {
        if (!Policy.validEdge(edge) || !ShelfTabs.find(id,edge)) return false;
        const key = Policy.key(output,edge);
        if (!root.isOpen(output,edge) && !root.toggle(output,edge)) return false;
        if (!root.update(output,edge,{tabs:[id]})) return false;
        root.selectedTabs = Object.assign({},root.selectedTabs,{[key]:id});
        return true;
    }
    function closeTab(output: string, edge: string): bool {
        if (!Policy.validEdge(edge) || root.tabFor(output,edge) === null) return false;
        root.selectedTabs = Object.assign({},root.selectedTabs,{[Policy.key(output,edge)]:""});
        return true;
    }
    function acknowledge(output: string, edge: string): void {
        if (!Settings.shelfTabAcknowledge || !Policy.validEdge(edge)) return;
        const key = Policy.key(output,edge);
        root._acks = Object.assign({},root._acks,{[key]:(root._acks[key] ?? 0) + 1});
        root.acksChanged();
    }
    function ackCount(output: string, edge: string): int { return root._acks[Policy.key(output,edge)] ?? 0; }
    function tabFor(output: string, edge: string): var {
        if (!Policy.validEdge(edge)) return null;
        const id = root.selectedTabs[Policy.key(output,edge)] ?? ShelfTabs.selected(output,edge);
        return id.length > 0 ? ShelfTabs.find(id,edge) : null;
    }
    // A visible handle is a standing affordance, so its window is a
    // deliberate cost the user opted into. Off means no window at all.
    function handleActive(output: string): bool {
        if (!root.outputNames.includes(output)) return false;
        const cfg = root.config(output);
        return (cfg.left.enabled && cfg.left.handles) || (cfg.right.enabled && cfg.right.handles);
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
