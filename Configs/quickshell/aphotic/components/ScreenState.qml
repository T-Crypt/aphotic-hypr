import Quickshell
import qs.services

PersistentProperties {
    id: root

    required property ShellScreen modelData

    // Drawer visibilities
    property bool bar
    property bool osd
    property bool session
    property bool launcher
    property bool dashboard
    property bool workspace
    property bool settings
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

    // Every flag above that is a surface reports its changes to
    // Surfaces, which decides what the change does to the rest of this
    // screen (services/SurfacePolicy.js). The flags stay the one way to
    // open or close anything; this is what makes them agree.
    property var surfaceStack: []

    // focusOwner / mode / blocking for this screen, recomputed only when
    // the stack or a blocking hold changes. The shape the visual layer
    // styles against rather than reading a dozen flags.
    readonly property var surface: Surfaces.describe(root.surfaceStack)
    readonly property bool engaged: Surfaces.engaged(root.surfaceStack)

    onSessionChanged: Surfaces.track(root, "session", root.session)
    onLauncherChanged: Surfaces.track(root, "launcher", root.launcher)
    onDashboardChanged: Surfaces.track(root, "dashboard", root.dashboard)
    onWorkspaceChanged: Surfaces.track(root, "workspace", root.workspace)
    onSettingsChanged: Surfaces.track(root, "settings", root.settings)
    onAgentPanelChanged: Surfaces.track(root, "agentPanel", root.agentPanel)
    onIntelligenceChanged: Surfaces.track(root, "intelligence", root.intelligence)
    onNotificationCenterChanged: Surfaces.track(root, "notificationCenter", root.notificationCenter)
    onPkgInstallChanged: Surfaces.track(root, "pkgInstall", root.pkgInstall)
    onWallpaperPickerChanged: Surfaces.track(root, "wallpaperPicker", root.wallpaperPicker)
    onKeybindsCheatsheetChanged: Surfaces.track(root, "keybindsCheatsheet", root.keybindsCheatsheet)
}
