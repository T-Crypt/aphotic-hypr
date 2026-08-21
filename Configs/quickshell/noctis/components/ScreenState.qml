import Quickshell

PersistentProperties {
    required property ShellScreen modelData

    // Drawer visibilities
    property bool bar
    property bool osd
    property bool session
    property bool launcher
    property bool dashboard
    property bool utilities
    property bool sidebar

    // Dashboard state
    property int dashboardTab
    property date dashboardDate: new Date()

    // Launcher: text the search box should start with the next time it
    // opens (e.g. "~" so SUPER+CTRL+W jumps straight to the theme/
    // wallpaper picker instead of plain app search). Cleared by the
    // launcher itself once consumed.
    property string launcherPrefill: ""
}
