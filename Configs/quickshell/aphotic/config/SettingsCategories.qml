pragma Singleton
import QtQuick
import qs.services

// Hoisted out of SettingsPanel.qml so the launcher's "?" settings-search
// mode (Launcher.qml) can search the same category list SettingsPanel's
// own CategoryRail renders, instead of a second hand-maintained copy that
// could drift out of sync with the real pane set.
//
// Plugin-contributed panes are appended to the same list for the same
// reason: a plugin's pane is searchable from the launcher and rendered by
// the rail off one list, not two. `plugin` is set only on those entries,
// which is how SettingsPanel picks the dynamic loader for them without
// knowing any plugin's id.
QtObject {
    id: root

    readonly property var list: root._core.concat(PluginRegistry.surfacesFor("settings").map(s => ({
        id: s.id,
        icon: s.icon,
        label: s.label,
        description: s.description ?? qsTr("Plugin settings"),
        plugin: s.plugin,
        componentUrl: s.componentUrl
    })))

    readonly property var _core: [
        { id: "appearance", icon: "palette", label: qsTr("Appearance"), description: qsTr("Theme, wallpaper, colors") },
        { id: "themeCreator", icon: "format_paint", label: qsTr("Theme Creator"), description: qsTr("Build a static custom theme") },
        { id: "personalization", icon: "face", label: qsTr("Personalization"), description: qsTr("Accent, cursor, icons") },
        { id: "language", icon: "keyboard", label: qsTr("Language"), description: qsTr("Keyboard layouts, input") },
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
        { id: "advanced", icon: "tune", label: qsTr("Advanced"), description: qsTr("Keyboard model, XKB rules") },
        { id: "about", icon: "info", label: qsTr("About"), description: qsTr("Version, credits") }
    ]
}
