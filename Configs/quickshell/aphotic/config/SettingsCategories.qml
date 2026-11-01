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

    // What a search box should match against: the categories, the sections
    // inside them, and the rows inside the panes. A plugin's pane stays
    // findable by name even though it is one expander deep, and a setting
    // found by its own words arrives with the address of the row that
    // carries it, which is the trade that keeps the rail short without
    // burying anything. Every entry carries a precomputed lowercase
    // searchKey so a keystroke is one substring test per entry.
    readonly property var searchIndex: root.list.map(c => ({
        id: c.id,
        icon: c.icon,
        label: c.label,
        description: c.description,
        searchKey: `${c.label} ${c.description}`.toLowerCase(),
        categoryId: c.id,
        sectionId: "",
        rowId: ""
    })).concat(root.pluginSections.map(s => ({
        id: `${s.parentId}/${s.id}`,
        icon: s.icon,
        label: s.label,
        description: qsTr("in %1").arg(root._core.find(c => c.id === s.parentId)?.label ?? s.parentId),
        searchKey: `${s.label} ${s.description}`.toLowerCase(),
        categoryId: s.parentId,
        sectionId: s.id,
        rowId: ""
    }))).concat(root._rows.map(r => ({
        id: `${r.category}//${r.anchor}`,
        icon: r.icon,
        label: r.label,
        description: qsTr("in %1").arg(root._core.find(c => c.id === r.category)?.label ?? r.category),
        searchKey: `${r.label} ${r.keywords}`.toLowerCase(),
        categoryId: r.category,
        sectionId: "",
        rowId: r.anchor
    })))

    // One entry per searchable setting row, anchored to the row component's
    // own `searchId` in its pane under modules/settings/panes. `keywords`
    // carries the words a user might type that the label does not contain.
    // The address is "<category>//<anchor>" (empty section, since these are
    // core pane rows, not plugin sections). Keep one entry per line in this
    // exact shape: tests/test_settings_search.py parses these lines and
    // fails when an entry and its pane row drift apart, in either
    // direction.
    readonly property var _rows: [
        { category: "appearance", anchor: "communityThemes", icon: "public", label: qsTr("Community themes"), keywords: "download index" },
        { category: "appearance", anchor: "browseWallpapers", icon: "grid_view", label: qsTr("Browse all wallpapers"), keywords: "gallery every" },
        { category: "appearance", anchor: "wallpaperPickerLayout", icon: "view_carousel", label: qsTr("Launcher layout"), keywords: "coverflow grid dock" },
        { category: "appearance", anchor: "dashboardLayout", icon: "space_dashboard", label: qsTr("Dashboard layout"), keywords: "dashboard layout spine signal super+d" },
        { category: "appearance", anchor: "windowOpacity", icon: "opacity", label: qsTr("Window opacity"), keywords: "transparency transparent see-through alpha" },
        { category: "appearance", anchor: "autoCycleWallpaper", icon: "slideshow", label: qsTr("Auto-cycle wallpaper"), keywords: "slideshow rotate random" },
        { category: "appearance", anchor: "cycleInterval", icon: "timer", label: qsTr("Interval"), keywords: "frequency minutes timer" },
        { category: "launcher", anchor: "resultsStyle", icon: "grid_view", label: qsTr("Results style"), keywords: "app search results grid list" },
        { category: "clock", anchor: "twelveHourClock", icon: "schedule", label: qsTr("12-hour clock"), keywords: "time format am pm" },
        { category: "clock", anchor: "barClockDate", icon: "calendar_month", label: qsTr("Show date in bar clock"), keywords: "day date bar" },
        { category: "clock", anchor: "desktopClock", icon: "nest_clock_farsight_analog", label: qsTr("Desktop clock"), keywords: "widget clock desktop" },
        { category: "clock", anchor: "weatherLocation", icon: "location_on", label: qsTr("Location"), keywords: "weather city geo ip" },
        { category: "clock", anchor: "weatherUnits", icon: "thermostat", label: qsTr("Units"), keywords: "celsius fahrenheit temperature weather" },
        { category: "osd", anchor: "osdEnabled", icon: "picture_in_picture", label: qsTr("Show OSD"), keywords: "overlay volume brightness on-screen display" },
        { category: "osd", anchor: "osdBrightness", icon: "brightness_6", label: qsTr("Brightness slider"), keywords: "brightness slider" },
        { category: "osd", anchor: "osdMicrophone", icon: "mic", label: qsTr("Microphone slider"), keywords: "mic volume slider" },
        { category: "osd", anchor: "osdHideDelay", icon: "timer", label: qsTr("OSD hide delay"), keywords: "timeout duration fade" },
        { category: "osd", anchor: "notifTimeout", icon: "notifications_active", label: qsTr("Notification timeout"), keywords: "expire popup toast duration" },
        { category: "displays", anchor: "displayResolution", icon: "aspect_ratio", label: qsTr("Resolution & refresh rate"), keywords: "hz monitor size mode" },
        { category: "displays", anchor: "displayScale", icon: "zoom_in", label: qsTr("Scale"), keywords: "dpi zoom scaling" },
        { category: "themeCreator", anchor: "themeName", icon: "edit", label: qsTr("Theme name"), keywords: "custom theme title" },
        { category: "themeCreator", anchor: "themeFolder", icon: "folder_open", label: qsTr("Theme folder"), keywords: "directory path custom theme" },
        { category: "network", anchor: "vpnConfig", icon: "vpn_key", label: qsTr("Config file"), keywords: "ovpn openvpn wireguard profile import" },
        { category: "network", anchor: "vpnAutoConnect", icon: "power_settings_new", label: qsTr("Auto-connect"), keywords: "login automatic vpn" },
        { category: "network", anchor: "vpnStatus", icon: "cable", label: qsTr("Status"), keywords: "connected vpn" },
        { category: "power", anchor: "screensaverIdle", icon: "screenshot_monitor", label: qsTr("Screensaver when idle"), keywords: "idle screensaver blank" },
        { category: "power", anchor: "screensaverAfter", icon: "timer", label: qsTr("Screensaver after"), keywords: "timeout minutes delay" },
        { category: "power", anchor: "lockIdle", icon: "lock_clock", label: qsTr("Lock when idle"), keywords: "idle lock" },
        { category: "power", anchor: "lockAfter", icon: "timer", label: qsTr("Lock after"), keywords: "timeout minutes lock" },
        { category: "power", anchor: "suspendIdle", icon: "bedtime", label: qsTr("Suspend when idle"), keywords: "idle suspend sleep" },
        { category: "power", anchor: "suspendAfter", icon: "timer", label: qsTr("Suspend after"), keywords: "timeout minutes sleep" },
        { category: "workspaceProfiles", anchor: "profileName", icon: "edit", label: qsTr("Profile name"), keywords: "new profile title" },
        { category: "workspaceProfiles", anchor: "profileCommand", icon: "terminal", label: qsTr("Command"), keywords: "launch exec command" },
        { category: "workspaceProfiles", anchor: "profileWorkspace", icon: "dashboard", label: qsTr("Workspace"), keywords: "target workspace open" },
        { category: "language", anchor: "kbLayout", icon: "keyboard", label: qsTr("Layout"), keywords: "keyboard layout language us" },
        { category: "language", anchor: "kbCustomCode", icon: "edit", label: qsTr("Custom code"), keywords: "xkb code custom" },
        { category: "language", anchor: "kbVariant", icon: "tune", label: qsTr("Variant"), keywords: "keyboard variant intl dvorak" },
        { category: "language", anchor: "kbAddLayout", icon: "add", label: qsTr("Add a layout"), keywords: "additional layout keyboard switch" },
        { category: "language", anchor: "kbSwitchKey", icon: "swap_horiz", label: qsTr("Switch key"), keywords: "switch keys shortcut cycles" },
        { category: "language", anchor: "kbModel", icon: "keyboard_alt", label: qsTr("Keyboard model"), keywords: "keyboard model hardware" },
        { category: "language", anchor: "kbRules", icon: "rule", label: qsTr("XKB rules"), keywords: "xkb rules keymap" },
        { category: "personalization", anchor: "depthEffects", icon: "blur_on", label: qsTr("Depth effects"), keywords: "frost blur transparency depth" },
        { category: "personalization", anchor: "cursorSize", icon: "photo_size_select_small", label: qsTr("Cursor size"), keywords: "mouse pointer px" },
        { category: "personalization", anchor: "iconAppMatch", icon: "pattern", label: qsTr("App match"), keywords: "app class desktop entry custom icon" },
        { category: "personalization", anchor: "customIcon", icon: "image", label: qsTr("Icon"), keywords: "glyph path theme custom" },
        { category: "personalization", anchor: "iconTreatAs", icon: "category", label: qsTr("Treat icon as"), keywords: "auto image glyph custom icon" },
        { category: "personalization", anchor: "statusIconBluetooth", icon: "bluetooth", label: qsTr("Bluetooth"), keywords: "bar status colour icon bluetooth" },
        { category: "personalization", anchor: "statusIconWifi", icon: "wifi", label: qsTr("Wi-Fi"), keywords: "bar status colour icon wifi network" },
        { category: "personalization", anchor: "statusIconPower", icon: "bolt", label: qsTr("Power profile"), keywords: "bar status colour icon power battery" },
        { category: "personalization", anchor: "statusIconPerformance", icon: "monitoring", label: qsTr("Performance"), keywords: "bar status colour icon performance cpu" },
        { category: "personalization", anchor: "statusIconHostInfo", icon: "lan", label: qsTr("Host info"), keywords: "bar status colour icon host" },
        { category: "personalization", anchor: "statusIconPomodoro", icon: "timer", label: qsTr("Pomodoro"), keywords: "bar status colour icon pomodoro timer" },
        { category: "personalization", anchor: "statusIconDnd", icon: "notifications_off", label: qsTr("Do Not Disturb"), keywords: "bar status colour icon dnd do not disturb" },
        { category: "personalization", anchor: "paletteAddAction", icon: "add", label: qsTr("Add an action"), keywords: "accent action slot palette" },
        { category: "bar", anchor: "dockBarRight", icon: "dock_to_right", label: qsTr("Dock bar to right edge"), keywords: "position edge dock right" },
        { category: "bar", anchor: "dockBarBottom", icon: "vertical_align_bottom", label: qsTr("Dock bar to bottom edge"), keywords: "position edge dock bottom" },
        { category: "bar", anchor: "barCompact", icon: "density_small", label: qsTr("Compact bar"), keywords: "density compact thin" },
        { category: "bar", anchor: "barHorizontal", icon: "swap_horiz", label: qsTr("Horizontal orientation"), keywords: "orientation horizontal vertical" },
        { category: "bar", anchor: "barCorners", icon: "rounded_corner", label: qsTr("Corners"), keywords: "radius rounding sharp soft round" },
        { category: "bar", anchor: "dockAutoHide", icon: "visibility_off", label: qsTr("Auto-hide when a window is focused"), keywords: "hide focus dock autohide" },
        { category: "bar", anchor: "dockMagnification", icon: "zoom_in", label: qsTr("Icon magnification on hover"), keywords: "magnify zoom hover dock" },
        { category: "bar", anchor: "taskbarGrouping", icon: "layers", label: qsTr("Group windows by app"), keywords: "group taskbar windows app" },
        { category: "bar", anchor: "minimalDnd", icon: "do_not_disturb_on", label: qsTr("Show Do Not Disturb indicator"), keywords: "dnd do not disturb indicator minimal" },
        { category: "bar", anchor: "capsuleMedia", icon: "music_note", label: qsTr("Show media in the capsule"), keywords: "media capsule player music" },
        { category: "bar", anchor: "capsuleExpand", icon: "pan_zoom", label: qsTr("Expand on hover"), keywords: "expand hover capsule open" },
        { category: "bar", anchor: "capsuleShapedArt", icon: "shapes", label: qsTr("Animated album artwork shape"), keywords: "album artwork shape animation" },
        { category: "bar", anchor: "capsuleAnimations", icon: "animation", label: qsTr("Animate transitions"), keywords: "animate transitions motion capsule" },
        { category: "sonar", anchor: "sonarEnabled", icon: "radar", label: qsTr("Enable Sonar"), keywords: "discovery ping sonar" },
        { category: "sonar", anchor: "sonarGhosts", icon: "visibility", label: qsTr("Show disabled-feature ghosts"), keywords: "ghosts disabled hints" },
        { category: "sonar", anchor: "sonarPingShortcut", icon: "keyboard_command_key", label: qsTr("Ping shortcut"), keywords: "shortcut keybind ping sonar" },
        { category: "sonar", anchor: "sonarPreview", icon: "play_arrow", label: qsTr("Preview ping"), keywords: "preview test ping" },
        { category: "sonar", anchor: "sonarLabels", icon: "label", label: qsTr("Labels from the last ping"), keywords: "labels ping targets" },
        { category: "sonar", anchor: "shelfOutput", icon: "monitor", label: qsTr("Shelf output"), keywords: "shelf monitor output display" },
        { category: "sonar", anchor: "shelfDockEnabled", icon: "dock_to_left", label: qsTr("Enable dock"), keywords: "dock shelf edge" },
        { category: "sonar", anchor: "shelfAllOutputs", icon: "monitor", label: qsTr("Running apps from all outputs"), keywords: "apps outputs monitors shelf" },
        { category: "sonar", anchor: "shelfMagnify", icon: "zoom_in", label: qsTr("Magnify icons"), keywords: "magnify zoom icons shelf" },
        { category: "sonar", anchor: "shelfPinned", icon: "apps", label: qsTr("Pinned desktop IDs"), keywords: "pinned apps desktop ids shelf" },
        { category: "sonar", anchor: "shelfHandles", icon: "touch_app", label: qsTr("Visible handle"), keywords: "handle grab shelf" },
        { category: "sonar", anchor: "shelfToggle", icon: "play_arrow", label: qsTr("Toggle shelf"), keywords: "toggle open close shelf" },
        { category: "sonar", anchor: "shelfLaunchEcho", icon: "bolt", label: qsTr("Launch echo"), keywords: "launch echo dock outline" },
        { category: "sonar", anchor: "shelfTabAcknowledge", icon: "touch_app", label: qsTr("Tab acknowledgement"), keywords: "tab acknowledgement trace" },
        { category: "sonar", anchor: "shelfNotchTabs", icon: "expand_more", label: qsTr("Show registered shelf tabs in the notch"), keywords: "notch tabs shelf plugins" },
        { category: "system", anchor: "updateCheck", icon: "update", label: qsTr("Pending update check"), keywords: "updates frequency daily weekly packages pacman" },
        { category: "ai", anchor: "aiHarnesses", icon: "terminal", label: qsTr("Coding agents"), keywords: "coding agents harness order default hidden rescan drop-in" },
        { category: "ai", anchor: "aiActive", icon: "smart_toy", label: qsTr("Active"), keywords: "provider active chat model" },
        { category: "ai", anchor: "aiModel", icon: "memory", label: qsTr("Model"), keywords: "ollama model selected" },
        { category: "ai", anchor: "aiInferenceMode", icon: "memory", label: qsTr("Inference mode"), keywords: "yield gpu idle inference" },
        { category: "ai", anchor: "aiPullModel", icon: "download", label: qsTr("Pull new model"), keywords: "download pull ollama model" },
        { category: "ai", anchor: "apiKeyClaude", icon: "key", label: qsTr("Claude (Anthropic)"), keywords: "api key anthropic claude" },
        { category: "ai", anchor: "apiKeyGemini", icon: "key", label: qsTr("Gemini"), keywords: "api key gemini google" },
        { category: "ai", anchor: "apiKeyChatgpt", icon: "key", label: qsTr("ChatGPT"), keywords: "api key chatgpt openai" },
        { category: "ai", anchor: "aiOllamaModels", icon: "folder", label: qsTr("Ollama models"), keywords: "models directory storage ollama" },
        { category: "ai", anchor: "aiGgufDir", icon: "folder_open", label: qsTr("GGUF directory"), keywords: "models gguf storage directory" },
        { category: "ai", anchor: "aiQuickChat", icon: "tune", label: qsTr("Quick-chat popout"), keywords: "intelligence overlay quick chat super shift a" },
        { category: "ai", anchor: "aiDefaultProvider", icon: "smart_toy", label: qsTr("Default provider"), keywords: "intelligence provider default" },
        { category: "ai", anchor: "aiDefaultModel", icon: "memory", label: qsTr("Default model"), keywords: "intelligence model default ollama" },
        { category: "ai", anchor: "aiSessionLimits", icon: "auto_delete", label: qsTr("Session limits"), keywords: "prune sessions limits history" },
        { category: "ai", anchor: "aiInstalledModel", icon: "smart_toy", label: qsTr("Installed model"), keywords: "claude assistant model installed" },
    ]

    readonly property var _core: [
        { id: "appearance", icon: "palette", label: qsTr("Appearance"), description: qsTr("Theme, wallpaper, colors"), group: qsTr("Look") },
        { id: "themeCreator", icon: "format_paint", label: qsTr("Theme Creator"), description: qsTr("Build a static custom theme"), group: qsTr("Look") },
        { id: "personalization", icon: "face", label: qsTr("Personalization"), description: qsTr("Accent, cursor, icons"), group: qsTr("Look") },
        { id: "bar", icon: "dock_to_bottom", label: qsTr("Bar"), description: qsTr("Position, density"), group: qsTr("Desktop") },
        { id: "launcher", icon: "grid_view", label: qsTr("Launcher"), description: qsTr("Results style"), group: qsTr("Desktop") },
        { id: "clock", icon: "schedule", label: qsTr("Clock / Date"), description: qsTr("Format, desktop clock"), group: qsTr("Desktop") },
        { id: "osd", icon: "notifications", label: qsTr("OSD / Notifications"), description: qsTr("Sliders, timeouts"), group: qsTr("Desktop") },
        { id: "displays", icon: "monitor", label: qsTr("Displays"), description: qsTr("Resolution, refresh rate"), group: qsTr("Desktop") },
        { id: "sonar", icon: "radar", label: qsTr("Sonar & Shelves"), description: qsTr("Discovery ping, side docks"), group: qsTr("Desktop") },
        { id: "language", icon: "keyboard", label: qsTr("Language"), description: qsTr("Keyboard layouts, input"), group: qsTr("Input") },
        { id: "workspaceProfiles", icon: "workspaces", label: qsTr("Workspace Profiles"), description: qsTr("Named one-key launch groups"), group: qsTr("Input") },
        { id: "ai", icon: "smart_toy", label: qsTr("AI"), description: qsTr("Provider, API keys"), group: qsTr("Services") },
        { id: "network", icon: "lan", label: qsTr("Network"), description: qsTr("VPN"), group: qsTr("Services") },
        { id: "power", icon: "shield", label: qsTr("Power & Security"), description: qsTr("Profile, idle, lock"), group: qsTr("Services") },
        { id: "plugins", icon: "extension", label: qsTr("Plugins"), description: qsTr("Browse, install, manage"), group: qsTr("Services") },
        { id: "system", icon: "monitor_heart", label: qsTr("System"), description: qsTr("Doctor, dependencies"), group: qsTr("System") },
        { id: "about", icon: "info", label: qsTr("About"), description: qsTr("Version, credits"), group: qsTr("System") }
    ]
}
