import Quickshell

PersistentProperties {
    required property ShellScreen modelData

    // Drawer visibilities
    property bool bar
    property bool osd
    property bool session
    property bool launcher
    property bool dashboard
    property bool settings
    property bool utilities
    property bool sidebar
    property bool agentPanel
    property bool intelligence
    property bool notificationCenter
    property bool pkgInstall
    property bool wallpaperPicker
    property bool keybindsCheatsheet

    // Dashboard state
    property int dashboardTab
    property date dashboardDate: new Date()

    // Launcher: text the search box should start with the next time it
    // opens (e.g. "~" so SUPER+CTRL+W jumps straight to the theme/
    // wallpaper picker instead of plain app search). Cleared by the
    // launcher itself once consumed.
    property string launcherPrefill: ""

    // Settings: category id to jump straight to the next time the panel
    // opens (set by the launcher's "?" settings-search mode). Cleared by
    // SettingsWindow itself once consumed -- same one-shot handoff shape
    // as launcherPrefill above.
    property string settingsCategory: ""
}
