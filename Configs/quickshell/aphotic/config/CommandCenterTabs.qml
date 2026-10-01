pragma Singleton
import QtQuick

QtObject {
    readonly property var list: [
        { id: "dashboard", icon: "dashboard", label: qsTranslate("DashboardContent", "Dashboard") },
        { id: "flow", icon: "hub", label: qsTranslate("DashboardContent", "Flow") },
        { id: "performance", icon: "monitoring", label: qsTranslate("DashboardContent", "Performance") },
        { id: "workspaces", icon: "grid_view", label: qsTranslate("DashboardContent", "Workspaces") },
        { id: "wallpapers", icon: "wallpaper", label: qsTranslate("DashboardContent", "Wallpapers") },
        { id: "aiChat", icon: "smart_toy", label: qsTranslate("DashboardContent", "AI Chat") }
    ]
}
