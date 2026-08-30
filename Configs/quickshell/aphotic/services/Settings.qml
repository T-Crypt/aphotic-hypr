pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Runtime user-toggleable settings, persisted to
// ~/.local/state/aphotic/settings.json (a sibling of theme.json, same
// FileView load/save pattern as services/Themes.qml) so the settings
// popout's toggles survive a shell restart instead of resetting to
// Config.qml's compile-time defaults every time.
Singleton {
    id: root

    readonly property string statePath: `${Quickshell.env("HOME")}/.local/state/aphotic/settings.json`

    property bool twelveHourClock: GlobalConfig.services.useTwelveHourClock
    property bool showClockDate: Config.bar.clock.showDate
    // "always" (always shown), "autohide" (collapses to a thin edge sliver,
    // reveals on hover -- the old barPersistent:false behavior, now a
    // proper named mode instead of just "not always visible"), or "hidden"
    // (collapses to nothing, no hover reveal at all -- for someone who
    // wants it gone gone).
    property string barVisibility: Config.bar.persistent ? "always" : "autohide"
    property bool desktopClockEnabled: Config.background.desktopClock.enabled
    property bool barPositionRight: false
    property bool barCompact: false
    // true = full-width bar docked to top/bottom, entries flow left-to-right.
    // false (default) = full-height bar docked to left/right, entries flow
    // top-to-bottom. Was named `barVertical` with this exact meaning
    // inverted (true meant horizontal) until the rename -- see settings.json
    // load below for the migration of existing users' persisted state.
    property bool barHorizontal: false
    property bool barPositionBottom: false
    // Expanded from a purely cosmetic "outer strip background" choice
    // into the master bar-style switch. "pill"/"square" still just mean
    // the existing Full-style bar with its rounded/sharp background
    // treatment (BarWrapper.qml's `background` StyledRect) -- unchanged.
    // "dock"/"taskbar" are new structural styles. "minimal" is
    // REPURPOSED: it used to mean "Full-style bar, border-only outline,
    // transparent fill" -- it now means the new Omarchy-inspired thin
    // icon-only strip (a real layout change, not a background tweak).
    // Anyone with a pre-existing `barSkin: "minimal"` in settings.json
    // gets the new structural style on next load, not the old outline
    // look -- a deliberate one-time behavior change, not a bug.
    property string barSkin: "pill"
    // Whichever of "pill"/"square" was last active, so cycling/switching
    // back to the "full" style (from dock/taskbar/minimal) restores the
    // user's own preference instead of hardcoding one.
    property string lastFullSkin: "pill"
    // Style names that have ever had their first-selection position
    // default applied (dock -> bottom, minimal -> top) -- applied once
    // ever per style, not every time it's re-selected, so a user's own
    // later position override sticks.
    property var barStyleDefaultsApplied: []

    readonly property string barStyle: ["dock", "taskbar", "minimal"].includes(barSkin) ? barSkin : "full"

    property bool dockAutoHide: false
    // Array of desktop-entry ids (DesktopEntry.id, e.g. "firefox") pinned
    // to the Dock style regardless of whether they're currently running.
    property var dockPinnedApps: []
    // macOS-style icon-proximity magnification on Dock's app row. Only
    // engages in horizontal placement (Settings.barHorizontal) -- side
    // placement has no real vertical-dock layout to magnify along.
    property bool dockMagnification: true
    property bool taskbarGrouping: true
    property bool minimalShowDnd: true

    // name: "full" | "dock" | "taskbar" | "minimal" -- the single entry
    // point for changing bar style, shared by the Settings tab, the CLI
    // (`aphotic bar style`), and the IPC handler below, so all three
    // paths apply the exact same first-selection-position-default and
    // lastFullSkin bookkeeping instead of three divergent copies.
    function setBarStyle(name: string): void {
        const valid = ["full", "dock", "taskbar", "minimal"];
        if (!valid.includes(name))
            return;

        if (name === "full") {
            root.barSkin = root.lastFullSkin;
            return;
        }

        if (!root.barStyleDefaultsApplied.includes(name)) {
            root.barStyleDefaultsApplied = [...root.barStyleDefaultsApplied, name];
            if (name === "dock") {
                root.barHorizontal = true;
                root.barPositionBottom = true;
            } else if (name === "minimal") {
                root.barHorizontal = true;
                root.barPositionBottom = false;
            } else if (name === "taskbar") {
                root.barHorizontal = true;
                root.barPositionBottom = true;
            }
        }

        root.barSkin = name;
    }

    function cycleBarStyle(): void {
        const order = ["full", "dock", "taskbar", "minimal"];
        const idx = order.indexOf(root.barStyle);
        root.setBarStyle(order[(idx + 1) % order.length]);
    }

    property string agentSelectedProvider: "claude"
    property bool agentGraphEnabled: true
    // Node budget and layout tick rate for the agent graph surface, never
    // its visual treatment -- every tier renders the same look. "auto"
    // resolves from the detected GPU and demotes a tier while Ollama holds
    // models resident (see services/ai/AgentGraphService.qml); "lite",
    // "standard" and "full" pin it. Defaults to "auto" rather than "full"
    // for the same reason depthEffects defaults to "subtle": nobody's
    // machine should pick up load from an upgrade it never opted into.
    property string agentGraphQuality: "auto"
    property string agentGraphAccent: ""
    property string ggufModelsDir: `${Quickshell.env("HOME")}/Models/gguf`

    property bool intelligenceEnabled: true
    // "" = inherit AiConfig.activeProvider/ollamaModel for new sessions --
    // non-empty overrides it, same "" = default convention as
    // accentColorOverride above. Only affects sessions created after the
    // change; existing sessions keep whatever provider/model they were
    // created with.
    property string intelligenceDefaultProvider: ""
    property string intelligenceDefaultModel: ""
    property int intelligenceMaxSessions: 50
    // 0 = never auto-prune by age.
    property int intelligenceAutoPruneDays: 30

    property bool assistantWelcomeShown: false

    // Suppresses notification popups only -- notifications still land in
    // Notifs.list (history), see services/Notifs.qml. Auto-engaged/released
    // by services/DoNotDisturb.qml's Pomodoro connection; persisted here so
    // a mid-DND SUPER+B shell restart doesn't silently drop it.
    property bool dndEnabled: false

    // Advances the wallpaper within the active theme on a Timer (see
    // services/WallpaperCycle.qml) -- interval in minutes.
    property bool wallpaperAutoCycleEnabled: false
    property int wallpaperAutoCycleInterval: 15

    // "" = auto-detect via IP geolocation (services/Weather.qml), non-empty
    // = geocoded via Open-Meteo's geocoding API (city/place name or
    // "lat,lon" both work since it's passed straight through as the query).
    property string weatherLocation: ""
    // "celsius" or "fahrenheit".
    property string weatherUnits: "celsius"

    property bool osdEnabled: Config.osd.enabled
    property int osdHideDelay: Config.osd.hideDelay
    property bool osdEnableBrightness: Config.osd.enableBrightness
    property bool osdEnableMicrophone: Config.osd.enableMicrophone

    property real notifExpireTimeout: GlobalConfig.notifs.defaultExpireTimeout

    // "" = use the active theme's own accent (Colours.qml's hardcoded
    // m3primary); non-empty overrides it. Purely additive -- doesn't touch
    // the wallust/theme pipeline at all.
    property string accentColorOverride: ""
    // Same "" = theme default, non-empty = override convention as
    // accentColorOverride above, one per status-bar icon that would
    // otherwise always just inherit the bar's blanket secondaryOnSurface
    // tint with no way to set it apart.
    property string statusIconBluetoothColor: ""
    property string statusIconWifiColor: ""
    property string statusIconPowerProfileColor: ""
    property string statusIconPerformanceColor: ""
    property string statusIconHostInfoColor: ""
    property string statusIconPomodoroColor: ""
    property string statusIconDndColor: ""

    // "Aphotic Depth" visual identity -- glow breathing + marine-snow
    // particles layered on top of the existing wallust theme (see
    // components/effects/BioluminescentGlow.qml, components/DepthLayer.qml,
    // services/DepthFx.qml). "off" disables both entirely (today's static
    // look); "subtle" (the first-install default) runs a reduced tier;
    // "full" is the complete treatment. Defaulting to "subtle" rather than
    // "full" so nobody's GPU load jumps on an upgrade without an explicit
    // opt-in to the strongest tier.
    property string depthEffects: "subtle"

    property string cursorTheme: "Bibata-Modern-Ice"
    property int cursorSize: 20
    // Papirus family, not an arbitrary icon theme, matches cmd_theme.sh's
    // papirus-folders per-theme accent recoloring (see startup.lua's old
    // comment) -- picking a non-Papirus theme here just loses that
    // recoloring, it isn't blocked outright.
    property string iconTheme: "Papirus-Dark"
    // adw-gtk3-dark, not Dracula/stock Adwaita-dark -- see _applyGtkTheme()
    // below for why.
    property string gtkTheme: "adw-gtk3-dark"
    // Gate for an Aphotic theme's own icon_theme/cursor_theme/gtk_theme pin
    // (theme.toml's [icons]/[gtk] tables, applied in Wallpapers.qml's
    // setWallpaper -- see themes/THEME_SPEC.md). false = a theme switch is
    // free to follow its pin for this property; flipped to true the moment
    // the matching PersonalizationPane picker is used manually, after
    // which theme switches never touch it again. A fresh install with no
    // manual picks yet quietly follows whichever theme is active.
    property bool iconThemeUserSet: false
    property bool cursorThemeUserSet: false
    property bool gtkThemeUserSet: false

    // Idle behavior, backed by hypridle (~/.config/hypr/hypridle.conf,
    // fully generated here -- see _applyIdleConfig -- no repo-tracked
    // template needed, same as settings.json/theme.json). All timeouts in
    // seconds.
    property bool idleLockEnabled: true
    property int idleLockTimeout: 600
    property int idleScreenOffTimeout: 630
    property bool idleSuspendEnabled: false
    property int idleSuspendTimeout: 1800

    // Root directories the launcher's "@" project-switcher mode scans for
    // git repos (each immediate/one-level-deep child dir containing a
    // .git). Empty means "not configured yet" -- Launcher.qml falls back
    // to ~/Projects and ~/repos itself rather than writing a default here.
    property var projectRoots: []

    // "list" (default, the original vertical row layout) or "grid" (a
    // Rofi-drun-style icon grid) -- only affects the app-search mode
    // (Launcher.qml's default, no prefix), every other prefix mode
    // (clipboard/emoji/windows/theme/wallpaper/project) always renders
    // as a list regardless of this setting.
    property string launcherStyle: "list"

    // Named, one-key launch groups: [{ name: string, entries: [{ command:
    // string, workspace: int }] }]. Not a live session snapshot -- Hyprland/
    // X11 apps don't support that -- just a fixed replay list dispatched via
    // `hyprctl dispatch exec [workspace N] <command>` per entry.
    property var workspaceProfiles: []

    // Raw-openvpn profile state (see commands/cmd_vpn.sh) -- user runtime
    // state, not an install-time profile/layer choice, so it lives here
    // rather than a new [network.vpn] block in a toml (ROADMAP_FEATURES.md
    // PART C's resolved config-location decision). vpnConfigPath empty =
    // not configured. vpnAutoConnect is read by `aphotic vpn autostart`,
    // called from startup.lua -- Settings.qml itself never shells out to
    // openvpn (that needs root; connect/disconnect stay CLI-only, this is
    // just the config the CLI reads).
    property string vpnConfigPath: ""
    property bool vpnAutoConnect: false

    readonly property real barInnerWidth: barStyle === "minimal" ? Tokens.sizes.bar.minimalInnerWidth : Tokens.sizes.bar.innerWidth * (barCompact ? 0.85 : 1)

    property bool _loaded: false
    property bool _writePending: false

    function _saveState(): void {
        if (!root._loaded)
            return;
        root._writePending = true;
        stateWriter.setText(JSON.stringify({
            twelveHourClock: root.twelveHourClock,
            showClockDate: root.showClockDate,
            barVisibility: root.barVisibility,
            desktopClockEnabled: root.desktopClockEnabled,
            barPositionRight: root.barPositionRight,
            barCompact: root.barCompact,
            barHorizontal: root.barHorizontal,
            barPositionBottom: root.barPositionBottom,
            barSkin: root.barSkin,
            lastFullSkin: root.lastFullSkin,
            barStyleDefaultsApplied: root.barStyleDefaultsApplied,
            dockAutoHide: root.dockAutoHide,
            dockPinnedApps: root.dockPinnedApps,
            dockMagnification: root.dockMagnification,
            taskbarGrouping: root.taskbarGrouping,
            minimalShowDnd: root.minimalShowDnd,
            agentSelectedProvider: root.agentSelectedProvider,
            agentGraphEnabled: root.agentGraphEnabled,
            agentGraphQuality: root.agentGraphQuality,
            agentGraphAccent: root.agentGraphAccent,
            ggufModelsDir: root.ggufModelsDir,
            assistantWelcomeShown: root.assistantWelcomeShown,
            dndEnabled: root.dndEnabled,
            wallpaperAutoCycleEnabled: root.wallpaperAutoCycleEnabled,
            wallpaperAutoCycleInterval: root.wallpaperAutoCycleInterval,
            weatherLocation: root.weatherLocation,
            weatherUnits: root.weatherUnits,
            osdEnabled: root.osdEnabled,
            osdHideDelay: root.osdHideDelay,
            osdEnableBrightness: root.osdEnableBrightness,
            osdEnableMicrophone: root.osdEnableMicrophone,
            notifExpireTimeout: root.notifExpireTimeout,
            accentColorOverride: root.accentColorOverride,
            statusIconBluetoothColor: root.statusIconBluetoothColor,
            statusIconWifiColor: root.statusIconWifiColor,
            statusIconPowerProfileColor: root.statusIconPowerProfileColor,
            statusIconPerformanceColor: root.statusIconPerformanceColor,
            statusIconHostInfoColor: root.statusIconHostInfoColor,
            statusIconPomodoroColor: root.statusIconPomodoroColor,
            statusIconDndColor: root.statusIconDndColor,
            depthEffects: root.depthEffects,
            cursorTheme: root.cursorTheme,
            cursorSize: root.cursorSize,
            iconTheme: root.iconTheme,
            gtkTheme: root.gtkTheme,
            iconThemeUserSet: root.iconThemeUserSet,
            cursorThemeUserSet: root.cursorThemeUserSet,
            gtkThemeUserSet: root.gtkThemeUserSet,
            idleLockEnabled: root.idleLockEnabled,
            idleLockTimeout: root.idleLockTimeout,
            idleScreenOffTimeout: root.idleScreenOffTimeout,
            idleSuspendEnabled: root.idleSuspendEnabled,
            idleSuspendTimeout: root.idleSuspendTimeout,
            projectRoots: root.projectRoots,
            launcherStyle: root.launcherStyle,
            workspaceProfiles: root.workspaceProfiles,
            vpnConfigPath: root.vpnConfigPath,
            vpnAutoConnect: root.vpnAutoConnect,
            intelligenceEnabled: root.intelligenceEnabled,
            intelligenceDefaultProvider: root.intelligenceDefaultProvider,
            intelligenceDefaultModel: root.intelligenceDefaultModel,
            intelligenceMaxSessions: root.intelligenceMaxSessions,
            intelligenceAutoPruneDays: root.intelligenceAutoPruneDays
        }, null, 2));
    }

    // Generates ~/.config/hypr/hypridle.conf from the properties above and
    // (re)starts the hypridle.service user unit so the change takes
    // effect immediately -- hypridle has no live-reload, only a restart
    // picks up a config change. `enable` is idempotent, safe to call every
    // time. Idle-triggered locking goes through the shell's own IPC
    // (aphotic shell lock engage -> Lock.qml's real Quickshell
    // WlSessionLock screen), not swaylock -- the swaylock BINARY is still
    // used elsewhere (the session menu's own Lock button, see
    // SessionContent.qml, deliberately not switched over yet), but the
    // idle path specifically goes through the Quickshell lock screen.
    // Pam.qml separately reuses swaylock's PAM service name
    // (/etc/pam.d/swaylock, package-provided) for its own auth.
    function _applyIdleConfig(): void {
        const lockCmd = "qs -c aphotic ipc call lock engage";
        const lines = [
            "general {",
            `    lock_cmd = ${lockCmd}`,
            `    before_sleep_cmd = ${lockCmd}`,
            "    after_sleep_cmd = hyprctl dispatch dpms on",
            "}"
        ];
        if (root.idleLockEnabled) {
            lines.push("listener {", `    timeout = ${root.idleLockTimeout}`, `    on-timeout = ${lockCmd}`, "}");
            lines.push("listener {", `    timeout = ${root.idleScreenOffTimeout}`, "    on-timeout = hyprctl dispatch dpms off", "    on-resume = hyprctl dispatch dpms on", "}");
        }
        if (root.idleSuspendEnabled)
            lines.push("listener {", `    timeout = ${root.idleSuspendTimeout}`, "    on-timeout = systemctl suspend", "}");

        const confPath = `${Quickshell.env("HOME")}/.config/hypr/hypridle.conf`;
        const script = root.idleLockEnabled || root.idleSuspendEnabled ? `mkdir -p "$(dirname '${confPath}')" && cat > '${confPath}' <<'APHOTIC_HYPRIDLE_EOF'\n${lines.join("\n")}\nAPHOTIC_HYPRIDLE_EOF\nsystemctl --user enable hypridle.service >/dev/null 2>&1; systemctl --user restart hypridle.service` : "systemctl --user disable --now hypridle.service >/dev/null 2>&1";
        idleApplyProc.command = ["sh", "-c", script];
        idleApplyProc.running = true;
    }

    Process {
        id: idleApplyProc
    }

    // Applies the current cursor/icon theme to the running session --
    // both the live compositor (hyprctl) and GTK apps (gsettings/dconf,
    // which already persists itself, but Hyprland's own cursor needs
    // reapplying every session since it's a runtime IPC call, not a
    // persisted setting). Fired once after initial load (whatever the
    // resolved value turned out to be) and again on every live change,
    // replacing the old unconditional hardcoded calls in startup.lua --
    // this is now the single source of truth instead of two places
    // fighting over it on every reboot.
    //
    // Split into two independent Process/functions (was one shared
    // Process running all 4 commands for any of cursorTheme/cursorSize/
    // iconTheme changing) -- a cursor pick used to also gsettings-set
    // the icon theme every time, and a rapid second click (theme pick,
    // or a size +/- bump) landing while the first script was still
    // mid-flight silently no-opped, since `running = true` on an
    // already-running Process doesn't restart it with the new command.
    // `exec()` always (re)launches immediately, so a newer pick preempts
    // an in-flight one instead of being dropped.
    function _applyCursor(): void {
        cursorApplyProc.exec(["sh", "-c", `hyprctl setcursor '${root.cursorTheme}' ${root.cursorSize}; gsettings set org.gnome.desktop.interface cursor-theme '${root.cursorTheme}'; gsettings set org.gnome.desktop.interface cursor-size ${root.cursorSize}`]);
    }

    function _applyIconTheme(): void {
        iconApplyProc.exec(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", root.iconTheme]);
    }

    // gsettings only reaches GTK apps -- Qt apps read their icon theme from
    // qt5ct/qt6ct's own conf file instead, so it needs its own sync path.
    // Both files have exactly one `icon_theme=` line each; a plain sed -i
    // is the same pattern cmd_sddm.sh already uses for this class of flat
    // single-key config file. Qt apps only re-read this on next launch, not
    // live, unlike GTK's gsettings-watched keys.
    function _applyQtIconTheme(): void {
        const home = Quickshell.env("HOME");
        const script = `for f in "${home}/.config/qt5ct/qt5ct.conf" "${home}/.config/qt6ct/qt6ct.conf"; do [ -f "$f" ] && sed -i "s/^icon_theme=.*/icon_theme=${root.iconTheme}/" "$f"; done`;
        qtIconThemeApplyProc.exec(["sh", "-c", script]);
    }

    // adw-gtk3-dark specifically, not Dracula or GTK's own bundled
    // Adwaita-dark -- see startup.lua's old comment (now redundant, this
    // is the real single source of truth): Dracula hardcodes its own
    // palette outright, and stock Adwaita-dark's SCSS-compiled headerbar/
    // window chrome ignores @define-color overrides, so only adw-gtk3-dark
    // actually reflects wallust's live recoloring (Configs/wallust/
    // templates/gtk.css). Was previously set once at Hyprland startup only
    // -- nothing reasserted it afterward, so an external tool (nwg-look,
    // lxappearance) changing it just stuck until next relogin, the same
    // class of bug cursor/icon theme already got fixed for above.
    function _applyGtkTheme(): void {
        gtkThemeApplyProc.exec(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", root.gtkTheme]);
    }

    Process {
        id: cursorApplyProc
    }

    Process {
        id: iconApplyProc
    }

    Process {
        id: qtIconThemeApplyProc
    }

    Process {
        id: gtkThemeApplyProc
    }

    onTwelveHourClockChanged: root._saveState()
    onShowClockDateChanged: root._saveState()
    onBarVisibilityChanged: root._saveState()
    onDesktopClockEnabledChanged: root._saveState()
    onBarPositionRightChanged: root._saveState()
    onBarCompactChanged: root._saveState()
    onBarHorizontalChanged: root._saveState()
    onBarPositionBottomChanged: root._saveState()
    onBarSkinChanged: {
        if (root.barSkin === "pill" || root.barSkin === "square")
            root.lastFullSkin = root.barSkin;
        root._saveState();
    }
    onLastFullSkinChanged: root._saveState()
    onBarStyleDefaultsAppliedChanged: root._saveState()
    onDockAutoHideChanged: root._saveState()
    onDockPinnedAppsChanged: root._saveState()
    onDockMagnificationChanged: root._saveState()
    onTaskbarGroupingChanged: root._saveState()
    onMinimalShowDndChanged: root._saveState()
    onGgufModelsDirChanged: root._saveState()
    onAssistantWelcomeShownChanged: root._saveState()
    onDndEnabledChanged: root._saveState()
    onWallpaperAutoCycleEnabledChanged: root._saveState()
    onWallpaperAutoCycleIntervalChanged: root._saveState()
    onWeatherLocationChanged: root._saveState()
    onWeatherUnitsChanged: root._saveState()
    onOsdEnabledChanged: root._saveState()
    onOsdHideDelayChanged: root._saveState()
    onOsdEnableBrightnessChanged: root._saveState()
    onOsdEnableMicrophoneChanged: root._saveState()
    onNotifExpireTimeoutChanged: root._saveState()
    onAccentColorOverrideChanged: root._saveState()
    onStatusIconBluetoothColorChanged: root._saveState()
    onStatusIconWifiColorChanged: root._saveState()
    onStatusIconPowerProfileColorChanged: root._saveState()
    onStatusIconPerformanceColorChanged: root._saveState()
    onStatusIconHostInfoColorChanged: root._saveState()
    onStatusIconPomodoroColorChanged: root._saveState()
    onStatusIconDndColorChanged: root._saveState()
    onDepthEffectsChanged: root._saveState()
    onCursorThemeChanged: {
        root._saveState();
        root._applyCursor();
    }
    onCursorSizeChanged: {
        root._saveState();
        root._applyCursor();
    }
    onIconThemeChanged: {
        root._saveState();
        root._applyIconTheme();
        root._applyQtIconTheme();
    }
    onGtkThemeChanged: {
        root._saveState();
        root._applyGtkTheme();
    }
    onIconThemeUserSetChanged: root._saveState()
    onCursorThemeUserSetChanged: root._saveState()
    onGtkThemeUserSetChanged: root._saveState()
    onIdleLockEnabledChanged: {
        root._saveState();
        root._applyIdleConfig();
    }
    onIdleLockTimeoutChanged: {
        root._saveState();
        root._applyIdleConfig();
    }
    onIdleScreenOffTimeoutChanged: {
        root._saveState();
        root._applyIdleConfig();
    }
    onIdleSuspendEnabledChanged: {
        root._saveState();
        root._applyIdleConfig();
    }
    onIdleSuspendTimeoutChanged: {
        root._saveState();
        root._applyIdleConfig();
    }
    onProjectRootsChanged: root._saveState()
    onLauncherStyleChanged: root._saveState()
    onWorkspaceProfilesChanged: root._saveState()
    onVpnConfigPathChanged: root._saveState()
    onVpnAutoConnectChanged: root._saveState()
    onIntelligenceEnabledChanged: root._saveState()
    onIntelligenceDefaultProviderChanged: root._saveState()
    onIntelligenceDefaultModelChanged: root._saveState()
    onIntelligenceMaxSessionsChanged: root._saveState()
    onIntelligenceAutoPruneDaysChanged: root._saveState()

    FileView {
        id: stateFile

        path: root.statePath
        watchChanges: true
        onLoaded: {
            if (root._writePending) {
                root._writePending = false;
                return;
            }
            try {
                const data = JSON.parse(text());
                if (typeof data.twelveHourClock === "boolean")
                    root.twelveHourClock = data.twelveHourClock;
                if (typeof data.showClockDate === "boolean")
                    root.showClockDate = data.showClockDate;
                if (typeof data.barVisibility === "string")
                    root.barVisibility = data.barVisibility;
                else if (typeof data.barPersistent === "boolean")
                    // Migrate the old boolean (pre-auto-hide) settings.json
                    // shape -- true meant always-visible, false meant the
                    // sliver/hover-reveal behavior that's now named
                    // "autohide" instead of just "not persistent".
                    root.barVisibility = data.barPersistent ? "always" : "autohide";
                if (typeof data.desktopClockEnabled === "boolean")
                    root.desktopClockEnabled = data.desktopClockEnabled;
                if (typeof data.barPositionRight === "boolean")
                    root.barPositionRight = data.barPositionRight;
                if (typeof data.barCompact === "boolean")
                    root.barCompact = data.barCompact;
                if (typeof data.barHorizontal === "boolean")
                    root.barHorizontal = data.barHorizontal;
                else if (typeof data.barVertical === "boolean")
                    // Migrate the pre-rename key -- `barVertical` was a
                    // misnomer (true actually meant horizontal placement,
                    // see the property declaration above), so the stored
                    // boolean carries over unchanged under the new name.
                    root.barHorizontal = data.barVertical;
                if (typeof data.barPositionBottom === "boolean")
                    root.barPositionBottom = data.barPositionBottom;
                if (typeof data.barSkin === "string")
                    root.barSkin = data.barSkin;
                if (typeof data.lastFullSkin === "string")
                    root.lastFullSkin = data.lastFullSkin;
                if (Array.isArray(data.barStyleDefaultsApplied))
                    root.barStyleDefaultsApplied = data.barStyleDefaultsApplied;
                if (typeof data.dockAutoHide === "boolean")
                    root.dockAutoHide = data.dockAutoHide;
                if (Array.isArray(data.dockPinnedApps))
                    root.dockPinnedApps = data.dockPinnedApps;
                if (typeof data.dockMagnification === "boolean")
                    root.dockMagnification = data.dockMagnification;
                if (typeof data.taskbarGrouping === "boolean")
                    root.taskbarGrouping = data.taskbarGrouping;
                if (typeof data.minimalShowDnd === "boolean")
                    root.minimalShowDnd = data.minimalShowDnd;
                if (typeof data.agentSelectedProvider === "string" && ["claude", "codex", "ollama"].includes(data.agentSelectedProvider))
                    root.agentSelectedProvider = data.agentSelectedProvider;
                if (typeof data.agentGraphEnabled === "boolean")
                    root.agentGraphEnabled = data.agentGraphEnabled;
                if (typeof data.agentGraphQuality === "string" && ["auto", "lite", "standard", "full"].includes(data.agentGraphQuality))
                    root.agentGraphQuality = data.agentGraphQuality;
                if (typeof data.agentGraphAccent === "string")
                    root.agentGraphAccent = data.agentGraphAccent;
                if (typeof data.ggufModelsDir === "string" && data.ggufModelsDir.length > 0)
                    root.ggufModelsDir = data.ggufModelsDir;
                if (typeof data.assistantWelcomeShown === "boolean")
                    root.assistantWelcomeShown = data.assistantWelcomeShown;
                if (typeof data.dndEnabled === "boolean")
                    root.dndEnabled = data.dndEnabled;
                if (typeof data.wallpaperAutoCycleEnabled === "boolean")
                    root.wallpaperAutoCycleEnabled = data.wallpaperAutoCycleEnabled;
                if (typeof data.wallpaperAutoCycleInterval === "number")
                    root.wallpaperAutoCycleInterval = data.wallpaperAutoCycleInterval;
                if (typeof data.weatherLocation === "string")
                    root.weatherLocation = data.weatherLocation;
                if (typeof data.weatherUnits === "string" && ["celsius", "fahrenheit"].includes(data.weatherUnits))
                    root.weatherUnits = data.weatherUnits;
                if (typeof data.osdEnabled === "boolean")
                    root.osdEnabled = data.osdEnabled;
                if (typeof data.osdHideDelay === "number")
                    root.osdHideDelay = data.osdHideDelay;
                if (typeof data.osdEnableBrightness === "boolean")
                    root.osdEnableBrightness = data.osdEnableBrightness;
                if (typeof data.osdEnableMicrophone === "boolean")
                    root.osdEnableMicrophone = data.osdEnableMicrophone;
                if (typeof data.notifExpireTimeout === "number")
                    root.notifExpireTimeout = data.notifExpireTimeout;
                if (typeof data.accentColorOverride === "string")
                    root.accentColorOverride = data.accentColorOverride;
                if (typeof data.statusIconBluetoothColor === "string")
                    root.statusIconBluetoothColor = data.statusIconBluetoothColor;
                if (typeof data.statusIconWifiColor === "string")
                    root.statusIconWifiColor = data.statusIconWifiColor;
                if (typeof data.statusIconPowerProfileColor === "string")
                    root.statusIconPowerProfileColor = data.statusIconPowerProfileColor;
                if (typeof data.statusIconPerformanceColor === "string")
                    root.statusIconPerformanceColor = data.statusIconPerformanceColor;
                if (typeof data.statusIconHostInfoColor === "string")
                    root.statusIconHostInfoColor = data.statusIconHostInfoColor;
                if (typeof data.statusIconPomodoroColor === "string")
                    root.statusIconPomodoroColor = data.statusIconPomodoroColor;
                if (typeof data.statusIconDndColor === "string")
                    root.statusIconDndColor = data.statusIconDndColor;
                if (typeof data.depthEffects === "string" && ["off", "subtle", "full"].includes(data.depthEffects))
                    root.depthEffects = data.depthEffects;
                if (typeof data.cursorTheme === "string")
                    root.cursorTheme = data.cursorTheme;
                if (typeof data.cursorSize === "number")
                    root.cursorSize = data.cursorSize;
                if (typeof data.iconTheme === "string")
                    root.iconTheme = data.iconTheme;
                if (typeof data.gtkTheme === "string")
                    root.gtkTheme = data.gtkTheme;
                if (typeof data.iconThemeUserSet === "boolean")
                    root.iconThemeUserSet = data.iconThemeUserSet;
                if (typeof data.cursorThemeUserSet === "boolean")
                    root.cursorThemeUserSet = data.cursorThemeUserSet;
                if (typeof data.gtkThemeUserSet === "boolean")
                    root.gtkThemeUserSet = data.gtkThemeUserSet;
                if (typeof data.idleLockEnabled === "boolean")
                    root.idleLockEnabled = data.idleLockEnabled;
                if (typeof data.idleLockTimeout === "number")
                    root.idleLockTimeout = data.idleLockTimeout;
                if (typeof data.idleScreenOffTimeout === "number")
                    root.idleScreenOffTimeout = data.idleScreenOffTimeout;
                if (typeof data.idleSuspendEnabled === "boolean")
                    root.idleSuspendEnabled = data.idleSuspendEnabled;
                if (typeof data.idleSuspendTimeout === "number")
                    root.idleSuspendTimeout = data.idleSuspendTimeout;
                if (Array.isArray(data.projectRoots))
                    root.projectRoots = data.projectRoots;
                if (typeof data.launcherStyle === "string")
                    root.launcherStyle = data.launcherStyle;
                if (Array.isArray(data.workspaceProfiles))
                    root.workspaceProfiles = data.workspaceProfiles;
                if (typeof data.vpnConfigPath === "string")
                    root.vpnConfigPath = data.vpnConfigPath;
                if (typeof data.vpnAutoConnect === "boolean")
                    root.vpnAutoConnect = data.vpnAutoConnect;
                if (typeof data.intelligenceEnabled === "boolean")
                    root.intelligenceEnabled = data.intelligenceEnabled;
                if (typeof data.intelligenceDefaultProvider === "string")
                    root.intelligenceDefaultProvider = data.intelligenceDefaultProvider;
                if (typeof data.intelligenceDefaultModel === "string")
                    root.intelligenceDefaultModel = data.intelligenceDefaultModel;
                if (typeof data.intelligenceMaxSessions === "number")
                    root.intelligenceMaxSessions = data.intelligenceMaxSessions;
                if (typeof data.intelligenceAutoPruneDays === "number")
                    root.intelligenceAutoPruneDays = data.intelligenceAutoPruneDays;
            } catch (e) {
                // No state file yet, or malformed -- keep the Config.qml/
                // GlobalConfig.qml defaults already set above.
            }
            root._loaded = true;
            // Whether the values above came from the state file or are
            // just the compile-time defaults, apply them now -- this is
            // what makes cursor/icon theme survive a reboot instead of
            // startup.lua's old hardcoded calls silently overwriting
            // whatever was chosen here on the next boot.
            root._applyCursor();
            root._applyIconTheme();
            root._applyQtIconTheme();
            root._applyGtkTheme();
            root._applyIdleConfig();
        }
        onLoadFailed: error => {
            root._loaded = true;
            root._applyCursor();
            root._applyIconTheme();
            root._applyQtIconTheme();
            root._applyGtkTheme();
            root._applyIdleConfig();
        }
    }

    FileView {
        id: stateWriter

        path: root.statePath
        printErrors: false
    }

    Process {
        id: mkStateDir
        command: ["mkdir", "-p", `${Quickshell.env("HOME")}/.local/state/aphotic`]
        onExited: stateFile.reload()
    }

    // `aphotic bar style <name>` and any future keybind/IPC quick-swap
    // both go through this rather than writing settings.json directly --
    // one source of truth (setBarStyle's own first-selection-default and
    // lastFullSkin bookkeeping), matching the IPC-toggle pattern every
    // other overlay/setting in this repo already uses.
    IpcHandler {
        function setStyle(name: string): void {
            root.setBarStyle(name);
        }

        function cycleStyle(): void {
            root.cycleBarStyle();
        }

        target: "bar"
    }

    Component.onCompleted: mkStateDir.running = true
}
