import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property ScreenState screenState
    property string currentTab: "dashboard"

    readonly property var tabs: [
        { id: "dashboard", icon: "dashboard", label: qsTr("Dashboard") },
        { id: "performance", icon: "monitoring", label: qsTr("Performance") },
        { id: "workspaces", icon: "grid_view", label: qsTr("Workspaces") },
        { id: "aiChat", icon: "smart_toy", label: qsTr("AI Chat") }
    ]

    spacing: Tokens.spacing.medium

    CommandCenterTabBar {
        Layout.alignment: Qt.AlignHCenter
        currentTab: root.currentTab
        tabs: root.tabs
        onTabSelected: id => root.currentTab = id
    }

    Loader {
        id: tabLoader

        Layout.alignment: Qt.AlignHCenter
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
        id: aiChatComp
        AiChatTab {}
    }
}
