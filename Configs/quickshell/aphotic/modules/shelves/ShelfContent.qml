pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.config
import qs.components
import qs.modules.bar
import "../../services/ShelfEchoPolicy.js" as Echo

// One edge's shelf. The dock icons are the default body; a selected tab
// replaces them with its panel, with a strip of handles above it. Both
// live inside the one fixed budget the reveal sizes, so opening a tab
// never grows the window.
Item {
    id: root
    required property string output
    required property string edge
    required property string screen
    readonly property var config: Shelves.config(output)[edge]
    readonly property var items: WindowList.dockItems(config.pinned,output,config.allOutputs)
    readonly property bool tabOpen: Shelves.tabFor(output,edge) !== null
    readonly property bool hasTabs: ShelfTabs.forEdge(edge).length > 0
    // The one key currently echoing, held here rather than per icon: two
    // icons can never show the same answer, and one string is cheaper than
    // a per-icon animation running at rest.
    readonly property string echoScope: root.output + ":" + root.edge + "/"
    readonly property string echoing: Settings.shelfLaunchEcho && ShelfLaunchEcho.echoing.startsWith(echoScope) ? ShelfLaunchEcho.echoing.slice(echoScope.length) : ""
    property var knownWindows: Hypr.toplevels.values.map(t => t.address)

    Connections {
        target: Hypr.toplevels
        function onValuesChanged() {
            root.checkEcho();
        }
    }

    function checkEcho(): void {
        const current = Hypr.toplevels.values;
        const added = Echo.newWindows(root.knownWindows,current);
        root.knownWindows = current.map(t => t.address);
        if (!Settings.shelfLaunchEcho || root.tabOpen) return;
        for (const t of added) {
            const appClass = t.lastIpcObject?.class ?? "";
            const entry = DesktopEntries.heuristicLookup(appClass);
            const item = root.items.find(i => i.key === entry?.id || i.key === appClass);
            if (item) ShelfLaunchEcho.observe(root.echoScope + item.key);
        }
    }

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer
    }
    MouseArea { objectName: "shelf-interior"; anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    // The tab handles, only when this edge has a tab to switch to.
    Loader {
        id: strip

        objectName: "shelf-tab-strip"
        anchors.top: parent.top
        anchors.topMargin: Tokens.padding.small
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        active: root.hasTabs
        sourceComponent: Component { ShelfTabStrip { output: root.output; edge: root.edge } }
    }

    Item {
        id: dockHost
        anchors.top: strip.bottom
        anchors.topMargin: strip.active ? Tokens.spacing.small : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: !root.tabOpen

        Flickable {
            id: scroll
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            clip: true
            contentWidth: width
            contentHeight: column.height
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: column
                width: scroll.width
                spacing: Tokens.spacing.small
                Repeater {
                    model: root.items
                    DockAppIcon {
                        id: icon
                        required property var modelData
                        item: modelData
                        width: scroll.width
                        height: Settings.barInnerWidth
                        animateScale: RenderGate.decorative
                        onLaunchRequested: key => ShelfLaunchEcho.request(root.echoScope + key)
                        magnifyScale: root.config.magnify && RenderGate.decorative && hover.hovered
                            ? 1 + 0.15 * Math.pow(Math.max(0,1 - Math.abs(icon.y + icon.height/2 - hover.point.position.y)/90),2) : 1
                        property QtObject _sonarTarget: Loader {
                            active: Settings.sonarEnabled
                            sourceComponent: EchoTarget {
                                target: icon
                                targetId: "core:shelf/" + root.edge + "/" + icon.item.key
                                label: icon.item.name
                            }
                        }

                        // The echo answers the launch this icon asked for,
                        // and only while the effect is on. The ring itself
                        // is off-screen most of the time, so a shelf nobody
                        // is echoing draws nothing extra.
                        ShelfEchoRing {
                            key: icon.item.key
                            echoing: icon.item.key === root.echoing
                        }
                    }
                }
            }
            HoverHandler { id: hover; enabled: root.config.magnify && RenderGate.decorative }
        }
    }

    // The tab panel, in the same budget. Lazy, and destroyed with the
    // shelf, so a closed shelf holds no plugin QML.
    Loader {
        id: panel

        objectName: "shelf-tab-panel"
        anchors.top: strip.bottom
        anchors.topMargin: strip.active ? Tokens.spacing.small : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        active: root.tabOpen
        sourceComponent: Component { ShelfTabPanel { output: root.output; edge: root.edge; screen: root.screen } }
    }
}