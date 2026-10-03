pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components
import qs.services

// One tab's content, wherever it is shown. The shelf edge and the notch
// both mount this rather than a loader of their own, so a plugin tab is
// offered the same placement and the same lifecycle in either host and
// there is only one answer about what a plugin receives.
Item {
    id: root

    required property var tab
    required property string output
    // Which shelf edge, or "notch" when the notch is the host. A plugin
    // reads this to know where it drew; it never chooses.
    required property string edge
    required property string screen
    required property bool active
    property bool acknowledge: false

    function ready(): void {
        const id = root.tab?.id;
        Qt.callLater(() => {
            if (root.acknowledge && root.active && root.tab?.id === id)
                Shelves.acknowledge(root.output,root.edge);
        });
    }

    Loader {
        anchors.fill: parent
        active: root.active && root.tab !== null && root.tab.core
        sourceComponent: active ? root.coreComponent(root.tab.id) : null
        onLoaded: root.ready()
    }

    Loader {
        id: pluginBody
        anchors.fill: parent
        active: root.active && root.tab !== null && !root.tab.core
        property string url: active ? root.tab.componentUrl : ""
        function load(): void {
            setSource(url,url ? {edge:root.edge,output:root.output,screen:root.screen,active:root.active} : {});
        }
        function supply(): void {
            if (!item) return;
            item.edge = root.edge;
            item.output = root.output;
            item.screen = root.screen;
            item.active = root.active;
        }
        onUrlChanged: load()
        Component.onCompleted: load()
        onLoaded: root.ready()
        Connections {
            target: root
            function onEdgeChanged(): void { pluginBody.supply(); }
            function onOutputChanged(): void { pluginBody.supply(); }
            function onScreenChanged(): void { pluginBody.supply(); }
            function onActiveChanged(): void { pluginBody.supply(); }
        }
    }

    function coreComponent(id: string): var {
        if (id === "media")
            return mediaTab;
        if (id === "quick")
            return quickTab;
        if (id === "agents")
            return agentsTab;
        return null;
    }

    Component { id: mediaTab; ShelfMediaTab {} }
    Component { id: quickTab; ShelfQuickTab {} }
    Component { id: agentsTab; ShelfAgentsTab { owner: "shelf-agents:" + root.output + ":" + root.edge } }
}