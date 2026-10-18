import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.modules.flow
import QtQuick.Window
import "spine"

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

    function _latchTab(): void {
        if (root._openedTabIds.includes(root.currentTab))
            return;
        if (!root.pluginTabs.some(t => t.id === root.currentTab))
            return;
        root._openedTabIds = root._openedTabIds.concat([root.currentTab]);
    }

    onCurrentTabChanged: root._latchTab()
    Component.onCompleted: {
        root._takeTabRequest();
        root._latchTab();
    }

    function _takeTabRequest(): void {
        const id = root.screenState.dashboardTabRequest;
        if (!id)
            return;
        root.screenState.dashboardTabRequest = "";
        if (root.tabs.some(t => t.id === id))
            root.currentTab = id;
    }

    Connections {
        target: root.screenState

        function onDashboardTabRequestChanged(): void {
            root._takeTabRequest();
        }
    }

    function stepTab(delta: int): void {
        const i = root.tabs.findIndex(t => t.id === root.currentTab);
        const next = Math.max(0, Math.min(root.tabs.length - 1, i + delta));
        if (next !== i)
            root.currentTab = root.tabs[next].id;
    }

    // Installed, enabled, and its own declared gate satisfied -- all three
    // decided by PluginRegistry off the plugin's manifest. This file knows
    // that dashboard tabs exist; it does not know that any particular
    // plugin does.
    readonly property var pluginTabs: PluginRegistry.surfacesFor("dashboard")

    // AI Chat is core, not layered: its remote backends are plain HTTP
    // APIs the `ai` layer does not install, so a base shell still chats
    // with them. The layer only supplies the locally-hosted backends, and
    // AiProviders drops those pills on its own -- so this tab stays, with
    // a shorter provider list. The plugin tabs appended below are the
    // genuinely layered ones, and stay gated.
    // The Spine already shows the machine live, so the Performance tab
    // only exists for the Classic layout.
    readonly property var tabs: CommandCenterTabs.list.filter(t => t.id !== "performance" || Settings.dashboardLayout !== "spine").concat(root.pluginTabs.map(t => ({id:t.id,icon:t.icon,label:t.label})))

    onTabsChanged: {
        if (!root.tabs.some(t => t.id === root.currentTab))
            root.currentTab = "dashboard";
    }

    spacing: Tokens.spacing.medium

    // Signal: the tabs sit on their own glass capsule.
    Item {
        Layout.alignment: Qt.AlignHCenter
        readonly property real pad: Tokens.padding.small
        implicitWidth: tabBar.implicitWidth + pad * 2
        implicitHeight: tabBar.implicitHeight + pad * 2

        StyledRect {
            anchors.fill: parent
            radius: Tokens.rounding.full
            color: Colours.signalStyle.glass
            border.width: 1
            border.color: Colours.signalStyle.hairline
        }

        CommandCenterTabBar {
            id: tabBar

            anchors.centerIn: parent
            currentTab: root.currentTab
            tabs: root.tabs
            onTabSelected: id => root.currentTab = id
        }

        // One accent bar that glides to whichever tab is active.
        StyledRect {
            visible: tabBar.activeTab !== null
            x: tabBar.x + (tabBar.activeTab?.x ?? 0) + Tokens.padding.large
            y: tabBar.y + tabBar.height - height - 2
            width: Math.max(0, (tabBar.activeTab?.width ?? 0) - Tokens.padding.large * 2)
            height: 2
            radius: Tokens.rounding.full
            color: Colours.signalStyle.accentLine

            Behavior on x {
                Anim { type: Anim.Emphasized }
            }
            Behavior on width {
                Anim { type: Anim.Emphasized }
            }
        }
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

        Elevation {
            target: tabFrame
            level: 2
        }

        Layout.alignment: Qt.AlignHCenter
        readonly property Item activeLoader: {
            const i = root.pluginTabs.findIndex(t => t.id === root.currentTab);
            if (i < 0 || i >= pluginTabRepeater.count)
                return tabLoader;
            return pluginTabRepeater.itemAt(i) ?? tabLoader;
        }

        readonly property real tabWidth: tabFrame.activeLoader.item?.implicitWidth ?? 0
        readonly property real tabHeight: tabFrame.activeLoader.item?.implicitHeight ?? 0

        // One stage for every tab, so switching never resizes the frame.
        // A tab larger than the stage still gets room, it just grows it.
        readonly property real stageWidth: Math.min(1680, (Window.width || 1280) - Tokens.padding.extraLarge * 4)
        readonly property real stageHeight: Math.min(940, (Window.height || 760) - Tokens.padding.extraLarge * 8)

        Layout.preferredWidth: Math.max(tabFrame.stageWidth, tabFrame.tabWidth) + Tokens.padding.extraLarge * 2
        Layout.preferredHeight: Math.max(tabFrame.stageHeight, tabFrame.tabHeight) + Tokens.padding.extraLarge * 2

        Behavior on Layout.preferredWidth {
            Anim { type: Anim.Emphasized }
        }
        Behavior on Layout.preferredHeight {
            Anim { type: Anim.Emphasized }
        }
        radius: Tokens.rounding.large
        color: Colours.signalStyle.glass
        border.width: 1
        border.color: Colours.signalStyle.hairline

        DepthLayer {
            anchors.fill: parent
            opacityScale: 0.7
        }

        DepthGradient {
            anchors.fill: parent
            visible: false
            radius: parent.radius
            baseColour: Colours.surfaceLift
        }

        Loader {
            id: tabLoader

            // Every tab gets the whole stage, edge to edge.
            anchors.fill: parent
            anchors.margins: Tokens.padding.extraLarge
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
                case "flow":
                    return flowComp;
                case "performance":
                    return performanceComp;
                case "workspaces":
                    return workspacesComp;
                case "wallpapers":
                    return wallpapersComp;
                case "aiChat":
                    return aiChatComp;
                default:
                    return Settings.dashboardLayout === "spine" ? spineComp : dashboardComp;
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

                anchors.fill: parent
                anchors.margins: Tokens.padding.extraLarge
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
        id: spineComp

        Item {
            SpineSurface {
                anchors.fill: parent
                embedded: true
            }
        }
    }
    Component {
        id: flowComp
        FlowTab {}
    }
    Component {
        id: performanceComp
        Loader {
            active: Config.dashboard.enabled
            sourceComponent: PerformanceTab {}
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
