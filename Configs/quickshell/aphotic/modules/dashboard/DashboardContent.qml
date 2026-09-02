import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.config
import qs.components
import qs.services
import qs.services.ai

ColumnLayout {
    id: root

    required property ScreenState screenState
    property string currentTab: "dashboard"

    // The graph surface is the most expensive thing the dashboard can
    // hold -- a GraphLayout and a full node/edge delegate tree, per
    // monitor -- and it used to be built as soon as the dashboard
    // content existed, whether or not anyone ever picked its tab.
    // Latched rather than tracking `currentTab` directly so switching
    // away keeps the built graph and its held layout positions.
    // Initial value covers starting *on* that tab, where no change signal
    // ever fires; the handler latches it for every later selection.
    property bool _agentGraphOpened: root.currentTab === "agentGraph"

    onCurrentTabChanged: {
        if (root.currentTab === "agentGraph")
            root._agentGraphOpened = true;
    }

    // Agent Graph is a plugin (docs/archive/PLUGIN_SYSTEM.md manifest v3),
    // not core -- its dashboard tab only exists when the "ai" layer is on
    // AND the plugin is installed+enabled AND at least one harness is
    // actually configured (APHOTIC_UNIFIED_VISION.md §2.4). The first two
    // are the generic plugin-system gate (PluginRegistry); the harness
    // check is this one plugin's own extra activation rule, not something
    // every ui-surface plugin needs, so it stays a call-site condition
    // rather than a manifest field.
    readonly property bool agentGraphAvailable: InstallProfile.aiEnabled && PluginRegistry.isEnabled("agent-graph") && AgentRoles.hasConfiguredHarness
    readonly property var _agentGraphTab: PluginRegistry.dashboardTabs.find(t => t.plugin === "agent-graph")

    // The AI tabs are absent, not empty, when the installer's `ai` layer is
    // off -- see services/InstallProfile.qml.
    readonly property var tabs: [
        { id: "dashboard", icon: "dashboard", label: qsTr("Dashboard") },
        { id: "performance", icon: "monitoring", label: qsTr("Performance") },
        { id: "workspaces", icon: "grid_view", label: qsTr("Workspaces") },
        { id: "wallpapers", icon: "wallpaper", label: qsTr("Wallpapers") }
    ].concat(InstallProfile.aiEnabled ? [
        { id: "aiChat", icon: "smart_toy", label: qsTr("AI Chat") }
    ] : []).concat(root.agentGraphAvailable && root._agentGraphTab ? [
        { id: root._agentGraphTab.id, icon: root._agentGraphTab.icon, label: root._agentGraphTab.label }
    ] : [])

    onTabsChanged: {
        if (!root.tabs.some(t => t.id === root.currentTab))
            root.currentTab = "dashboard";
    }

    spacing: Tokens.spacing.medium

    CommandCenterTabBar {
        Layout.alignment: Qt.AlignHCenter
        currentTab: root.currentTab
        tabs: root.tabs
        onTabSelected: id => root.currentTab = id
    }

    // Widget-card frame around whichever tab is active -- previously each
    // tab's own content floated directly on the desktop with only its
    // individual sub-cards (clock, calendar, media, ...) carrying a
    // background, so gaps between them showed raw wallpaper through and
    // the whole thing read as loose floating text rather than one
    // cohesive panel. This wraps the Loader itself, so every tab gets the
    // same bounded, bordered "floating tile" look for free rather than
    // each tab needing to build its own outer frame.
    StyledRect {
        id: tabFrame

        Layout.alignment: Qt.AlignHCenter
        // Whichever loader owns the active tab; both report 0 while one is
        // unloading and the other is still building, which is every first
        // switch to the graph now that it loads on demand. Holding the
        // last real size across that gap is what stops the frame
        // collapsing to bare padding and springing back open.
        readonly property real tabWidth: root.currentTab === "agentGraph" ? agentGraphLoader.implicitWidth : tabLoader.implicitWidth
        readonly property real tabHeight: root.currentTab === "agentGraph" ? agentGraphLoader.implicitHeight : tabLoader.implicitHeight

        property real heldWidth: 0
        property real heldHeight: 0

        onTabWidthChanged: if (tabFrame.tabWidth > 0) tabFrame.heldWidth = tabFrame.tabWidth
        onTabHeightChanged: if (tabFrame.tabHeight > 0) tabFrame.heldHeight = tabFrame.tabHeight

        Layout.preferredWidth: (tabFrame.tabWidth > 0 ? tabFrame.tabWidth : tabFrame.heldWidth) + Tokens.padding.extraLarge * 2
        Layout.preferredHeight: (tabFrame.tabHeight > 0 ? tabFrame.tabHeight : tabFrame.heldHeight) + Tokens.padding.extraLarge * 2
        radius: Tokens.rounding.extraLarge
        color: Qt.alpha(Colours.tPalette.m3surfaceContainer, 0.85)
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: 0.5
            shadowBlur: 0.5
            shadowVerticalOffset: 2
        }

        DepthLayer {
            anchors.fill: parent
            opacityScale: 0.7
        }

        DepthGradient {
            anchors.fill: parent
            radius: parent.radius
            baseColour: Colours.tPalette.m3surfaceContainer
        }

        Loader {
            id: tabLoader

            anchors.centerIn: parent
            opacity: 1
            active: true

            // Cross-fades between tabs on the same Anim.Emphasized curve the
            // bar popouts use, rather than a bespoke transition -- see
            // popouts/Wrapper.qml.
            Behavior on opacity {
                Anim { type: Anim.DefaultEffects }
            }

            sourceComponent: {
                switch (root.currentTab) {
                case "performance":
                    return performanceComp;
                case "workspaces":
                    return workspacesComp;
                case "wallpapers":
                    return wallpapersComp;
                case "aiChat":
                    return aiChatComp;
                case "agentGraph":
                    return null;
                default:
                    return dashboardComp;
                }
            }

            onSourceComponentChanged: {
                opacity = 0;
                fadeInTimer.restart();
            }

            Timer {
                id: fadeInTimer
                interval: 1
                onTriggered: tabLoader.opacity = 1
            }
        }

        Loader {
            id: agentGraphLoader

            anchors.centerIn: parent
            // No static `import` of the plugin's own QML module anywhere
            // in core -- `source` is a plain file:// URL resolved from
            // the plugin registry, so the shell compiles and runs
            // identically whether or not this plugin is installed.
            active: root.agentGraphAvailable && root._agentGraphTab !== undefined && root._agentGraphOpened
            asynchronous: true
            visible: agentGraphLoader.opacity > 0
            opacity: root.currentTab === "agentGraph" ? 1 : 0
            source: root.agentGraphAvailable && root._agentGraphTab ? root._agentGraphTab.componentUrl : ""

            Behavior on opacity {
                Anim { type: Anim.DefaultEffects }
            }
        }
    }

    Component {
        id: dashboardComp
        DashboardTab {}
    }
    Component {
        id: performanceComp
        Loader {
            active: Config.dashboard.enabled
            sourceComponent: Dashboard {}
        }
    }
    Component {
        id: workspacesComp
        WorkspacesTab {
            screenState: root.screenState
        }
    }
    Component {
        id: wallpapersComp
        DashWallpapersTab {}
    }
    Component {
        id: aiChatComp
        AiChatTab {}
    }
}
