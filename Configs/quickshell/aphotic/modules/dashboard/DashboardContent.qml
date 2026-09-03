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

    // Latched rather than tracking `currentTab` so switching away keeps a
    // plugin tab's built content and its laid-out state. Plain state, not a
    // binding seeded from `currentTab`: a seeded binding stays live until
    // the first imperative write, so starting on such a tab and switching
    // away would re-evaluate it and tear the content down again.
    property var _openedTabIds: []

    // PluginRegistry already gates on installed+enabled. Agent Graph is the
    // one plugin with an extra activation rule of its own -- the "ai" layer
    // on and at least one harness actually configured
    // (APHOTIC_UNIFIED_VISION.md §2.4). That is this plugin's rule, not a
    // plugin-system concept, so it lives here rather than in the manifest.
    function _extraGate(plugin: string): bool {
        if (plugin === "agent-graph")
            return InstallProfile.aiEnabled && AgentRoles.hasConfiguredHarness;
        return true;
    }

    function _latchTab(): void {
        if (root._openedTabIds.includes(root.currentTab))
            return;
        if (!root.pluginTabs.some(t => t.id === root.currentTab))
            return;
        root._openedTabIds = root._openedTabIds.concat([root.currentTab]);
    }

    onCurrentTabChanged: root._latchTab()
    Component.onCompleted: root._latchTab()

    readonly property var pluginTabs: PluginRegistry.dashboardTabs.filter(t => root._extraGate(t.plugin))

    // AI Chat is core, not layered: Claude is a CLI session and Gemini and
    // ChatGPT are raw HTTP APIs, none of which the `ai` layer installs, so
    // a base shell still chats with all three. The layer only supplies the
    // locally-hosted backends, and AiProviders drops those pills on its own
    // -- so this tab stays, with a shorter provider list. The plugin tabs
    // appended below are the genuinely layered ones, and stay gated.
    readonly property var tabs: [
        { id: "dashboard", icon: "dashboard", label: qsTr("Dashboard") },
        { id: "performance", icon: "monitoring", label: qsTr("Performance") },
        { id: "workspaces", icon: "grid_view", label: qsTr("Workspaces") },
        { id: "wallpapers", icon: "wallpaper", label: qsTr("Wallpapers") },
        { id: "aiChat", icon: "smart_toy", label: qsTr("AI Chat") }
    ].concat(root.pluginTabs.map(t => ({ id: t.id, icon: t.icon, label: t.label })))

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
        // Both the outgoing and incoming loader report 0 while one unloads
        // and the other builds async, which is every first switch to a
        // plugin tab now that they load on demand. Holding the last real
        // size across that gap is what stops the frame collapsing to bare
        // padding.
        readonly property Item activeLoader: {
            const i = root.pluginTabs.findIndex(t => t.id === root.currentTab);
            if (i < 0 || i >= pluginTabRepeater.count)
                return tabLoader;
            return pluginTabRepeater.itemAt(i) ?? tabLoader;
        }

        readonly property real tabWidth: tabFrame.activeLoader.implicitWidth
        readonly property real tabHeight: tabFrame.activeLoader.implicitHeight

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
                if (root.pluginTabs.some(t => t.id === root.currentTab))
                    return null;

                switch (root.currentTab) {
                case "performance":
                    return performanceComp;
                case "workspaces":
                    return workspacesComp;
                case "wallpapers":
                    return wallpapersComp;
                case "aiChat":
                    return aiChatComp;
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

        Repeater {
            id: pluginTabRepeater

            model: root.pluginTabs

            // No static `import` of any plugin's own QML module anywhere
            // in core -- `source` is a plain file:// URL resolved from
            // the plugin registry, so the shell compiles and runs
            // identically whether or not a given plugin is installed.
            Loader {
                id: pluginTabLoader

                required property var modelData

                anchors.centerIn: parent
                active: root._openedTabIds.includes(pluginTabLoader.modelData.id)
                asynchronous: true
                visible: pluginTabLoader.opacity > 0
                opacity: root.currentTab === pluginTabLoader.modelData.id ? 1 : 0
                source: pluginTabLoader.modelData.componentUrl

                Behavior on opacity {
                    Anim { type: Anim.DefaultEffects }
                }
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
