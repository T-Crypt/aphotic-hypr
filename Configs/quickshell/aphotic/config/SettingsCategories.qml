pragma Singleton
import QtQuick

// Hoisted out of SettingsPanel.qml so the launcher's "?" settings-search
// mode (Launcher.qml) can search the same category list SettingsPanel's
// own CategoryRail renders, instead of a second hand-maintained copy that
// could drift out of sync with the real pane set.
QtObject {
    readonly property var list: [
        { id: "appearance", icon: "palette", label: qsTr("Appearance"), description: qsTr("Theme, wallpaper, colors") },
        { id: "themeCreator", icon: "format_paint", label: qsTr("Theme Creator"), description: qsTr("Build a static custom theme") },
        { id: "personalization", icon: "face", label: qsTr("Personalization"), description: qsTr("Accent, cursor, icons") },
        { id: "bar", icon: "dock_to_bottom", label: qsTr("Bar"), description: qsTr("Position, density") },
        { id: "launcher", icon: "grid_view", label: qsTr("Launcher"), description: qsTr("Results style") },
        { id: "displays", icon: "monitor", label: qsTr("Displays"), description: qsTr("Resolution, refresh rate") },
        { id: "clock", icon: "schedule", label: qsTr("Clock / Date"), description: qsTr("Format, desktop clock") },
        { id: "osd", icon: "notifications", label: qsTr("OSD / Notifications"), description: qsTr("Sliders, timeouts") },
        { id: "ai", icon: "smart_toy", label: qsTr("AI"), description: qsTr("Provider, API keys") },
        { id: "power", icon: "shield", label: qsTr("Power & Security"), description: qsTr("Profile, idle, lock") },
        { id: "network", icon: "lan", label: qsTr("Network"), description: qsTr("VPN") },
        { id: "workspaceProfiles", icon: "workspaces", label: qsTr("Workspace Profiles"), description: qsTr("Named one-key launch groups") },
        { id: "plugins", icon: "extension", label: qsTr("Plugins"), description: qsTr("Browse, install, manage") },
        { id: "system", icon: "monitor_heart", label: qsTr("System"), description: qsTr("Doctor, dependencies") },
        { id: "about", icon: "info", label: qsTr("About"), description: qsTr("Version, credits") }
    ]
}
