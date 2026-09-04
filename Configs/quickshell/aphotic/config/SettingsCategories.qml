pragma Singleton
import QtQuick
import qs.services

// Hoisted out of SettingsPanel.qml so the launcher's "?" settings-search
// mode (Launcher.qml) can search the same category list SettingsPanel's
// own CategoryRail renders, instead of a second hand-maintained copy that
// could drift out of sync with the real pane set.
//
// Plugin panes are deliberately NOT categories. A rail that grows one
// entry per plugin does not survive a plugin ecosystem -- fifty plugins
// would be fifty pages to scroll past, and they would sit after About,
// which is always meant to be last. They dock into an owning category's
// pane as collapsed sections instead (see sectionsFor), and stay findable
// through searchIndex.
QtObject {
    id: root

    // The rail's own list. FIXED length by design: a plugin never becomes
    // a rail entry, and nothing here grows with plugin count. About is
    // pinned last rather than merely written last, so an addition here
    // cannot quietly displace it.
    readonly property var list: root._core.filter(c => c.id !== "about").concat(root._core.filter(c => c.id === "about"))

    readonly property var _ids: root._core.map(c => c.id)

    // Every plugin-contributed settings pane, resolved to the category
    // whose pane hosts it as a collapsed section. A `parent` naming a
    // category that does not exist (a Dev plugin today -- there is no Dev
    // category, and inventing an otherwise-empty one would recreate the
    // thin-pane problem this design removes) falls back to the Plugins
    // pane rather than vanishing.
    readonly property var pluginSections: PluginRegistry.surfacesFor("settings").map(s => ({
        id: s.id,
        icon: s.icon,
        label: s.label,
        description: s.description ?? qsTr("Plugin settings"),
        plugin: s.plugin,
        componentUrl: s.componentUrl,
        parentId: root._ids.includes(s.parent) ? s.parent : "plugins"
    }))

    function sectionsFor(category: string): var {
        return root.pluginSections.filter(s => s.parentId === category);
    }

    // What a search box should match against: the categories AND the
    // sections inside them. A plugin's pane stays findable by name even
    // though it is one expander deep -- which is the trade that keeps the
    // rail short without burying anything.
    readonly property var searchIndex: root.list.map(c => ({
        id: c.id,
        icon: c.icon,
        label: c.label,
        description: c.description,
        categoryId: c.id,
        sectionId: ""
    })).concat(root.pluginSections.map(s => ({
        id: `${s.parentId}/${s.id}`,
        icon: s.icon,
        label: s.label,
        description: qsTr("in %1").arg(root._core.find(c => c.id === s.parentId)?.label ?? s.parentId),
        categoryId: s.parentId,
        sectionId: s.id
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
        { id: "about", icon: "info", label: qsTr("About"), description: qsTr("Version, credits") }
    ]
}
