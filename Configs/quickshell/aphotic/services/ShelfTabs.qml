pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services
import "ShelfTabPolicy.js" as TabPolicy

// Every tab a shelf edge can host, core and plugin, addressed by one list.
// Read-only: it resolves what exists and never mounts anything, so a
// hidden shelf costs no plugin QML. The host decides what to load from the
// entry this returns.
Singleton {
    id: root

    // Core tabs read the services the shell already runs. Media reuses the
    // existing player list rather than starting a second watcher, quick
    // controls reuse the same network/DND state, and the agents tab is
    // gated on the install the way every other AI surface is.
    readonly property var coreTabs: [
        { id: "media", label: qsTr("Media"), icon: "music_note", componentUrl: "", core: true, edges: ["left", "right"], notch: false },
        { id: "agents", label: qsTr("Agents"), icon: "smart_toy", componentUrl: "", core: true, edges: ["left", "right"], notch: false,
            available: InstallProfile.aiEnabled },
        { id: "quick", label: qsTr("Quick controls"), icon: "bolt", componentUrl: "", core: true, edges: ["left", "right"], notch: false }
    ].filter(t => t.available !== false)

    // Plugin tabs come from the same registry every other surface kind
    // uses, gated by safe mode, the user's own disable and the manifest's
    // layer/data activation. A malformed declaration is dropped here
    // rather than reaching a Loader.
    readonly property var pluginTabs: {
        const surfaces = PluginRegistry.surfacesFor("edge_tab");
        const result = [];
        for (const surface of surfaces) {
            const tab = TabPolicy.pluginTab(surface);
            if (tab !== null)
                result.push(Object.assign({ core: false }, tab));
        }
        return result;
    }

    readonly property var tabs: root.coreTabs.concat(root.pluginTabs)

    // The notch takes the same registered content, but only the plugin tabs
    // that declared notch compatibility and only while the user asked for
    // it. It never adds a tile or a resting-shape change of its own.
    readonly property var notchTabs: Settings.shelfNotchTabs ? TabPolicy.notchTabs(root.pluginTabs) : []

    function forEdge(edge: string): var { return TabPolicy.forEdge(root.tabs, edge); }
    function find(id: string, edge: string): var { return TabPolicy.find(root.tabs, id, edge); }
    function selected(output: string, edge: string): string {
        return TabPolicy.selected(root.tabs, Shelves.config(output)[edge].tabs, edge);
    }
}