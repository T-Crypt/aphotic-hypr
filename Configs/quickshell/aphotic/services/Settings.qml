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
    property bool barVertical: false
    property bool barPositionBottom: false

    property bool osdEnabled: Config.osd.enabled
    property int osdHideDelay: Config.osd.hideDelay
    property bool osdEnableBrightness: Config.osd.enableBrightness
    property bool osdEnableMicrophone: Config.osd.enableMicrophone

    property real notifExpireTimeout: GlobalConfig.notifs.defaultExpireTimeout

    // "" = use the active theme's own accent (Colours.qml's hardcoded
    // m3primary); non-empty overrides it. Purely additive -- doesn't touch
    // the wallust/theme pipeline at all.
    property string accentColorOverride: ""
    property string cursorTheme: "Bibata-Modern-Ice"
    property int cursorSize: 20
    // Papirus family, not an arbitrary icon theme, matches cmd_theme.sh's
    // papirus-folders per-theme accent recoloring (see startup.lua's old
    // comment) -- picking a non-Papirus theme here just loses that
    // recoloring, it isn't blocked outright.
    property string iconTheme: "Papirus-Dark"

    // Idle behavior, backed by hypridle (~/.config/hypr/hypridle.conf,
    // fully generated here -- see _applyIdleConfig -- no repo-tracked
    // template needed, same as settings.json/theme.json). All timeouts in
    // seconds.
    property bool idleLockEnabled: true
    property int idleLockTimeout: 600
    property int idleScreenOffTimeout: 630
    property bool idleSuspendEnabled: false
    property int idleSuspendTimeout: 1800

    readonly property real barInnerWidth: Tokens.sizes.bar.innerWidth * (barCompact ? 0.85 : 1)

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
            barVertical: root.barVertical,
            barPositionBottom: root.barPositionBottom,
            osdEnabled: root.osdEnabled,
            osdHideDelay: root.osdHideDelay,
            osdEnableBrightness: root.osdEnableBrightness,
            osdEnableMicrophone: root.osdEnableMicrophone,
            notifExpireTimeout: root.notifExpireTimeout,
            accentColorOverride: root.accentColorOverride,
            cursorTheme: root.cursorTheme,
            cursorSize: root.cursorSize,
            iconTheme: root.iconTheme,
            idleLockEnabled: root.idleLockEnabled,
            idleLockTimeout: root.idleLockTimeout,
            idleScreenOffTimeout: root.idleScreenOffTimeout,
            idleSuspendEnabled: root.idleSuspendEnabled,
            idleSuspendTimeout: root.idleSuspendTimeout
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
    function _applyPersonalization(): void {
        personalizationApplyProc.command = ["sh", "-c", `hyprctl setcursor '${root.cursorTheme}' ${root.cursorSize}; gsettings set org.gnome.desktop.interface cursor-theme '${root.cursorTheme}'; gsettings set org.gnome.desktop.interface cursor-size ${root.cursorSize}; gsettings set org.gnome.desktop.interface icon-theme '${root.iconTheme}'`];
        personalizationApplyProc.running = true;
    }

    Process {
        id: personalizationApplyProc
    }

    onTwelveHourClockChanged: root._saveState()
    onShowClockDateChanged: root._saveState()
    onBarVisibilityChanged: root._saveState()
    onDesktopClockEnabledChanged: root._saveState()
    onBarPositionRightChanged: root._saveState()
    onBarCompactChanged: root._saveState()
    onBarVerticalChanged: root._saveState()
    onBarPositionBottomChanged: root._saveState()
    onOsdEnabledChanged: root._saveState()
    onOsdHideDelayChanged: root._saveState()
    onOsdEnableBrightnessChanged: root._saveState()
    onOsdEnableMicrophoneChanged: root._saveState()
    onNotifExpireTimeoutChanged: root._saveState()
    onAccentColorOverrideChanged: root._saveState()
    onCursorThemeChanged: {
        root._saveState();
        root._applyPersonalization();
    }
    onCursorSizeChanged: {
        root._saveState();
        root._applyPersonalization();
    }
    onIconThemeChanged: {
        root._saveState();
        root._applyPersonalization();
    }
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
                if (typeof data.barVertical === "boolean")
                    root.barVertical = data.barVertical;
                if (typeof data.barPositionBottom === "boolean")
                    root.barPositionBottom = data.barPositionBottom;
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
                if (typeof data.cursorTheme === "string")
                    root.cursorTheme = data.cursorTheme;
                if (typeof data.cursorSize === "number")
                    root.cursorSize = data.cursorSize;
                if (typeof data.iconTheme === "string")
                    root.iconTheme = data.iconTheme;
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
            root._applyPersonalization();
            root._applyIdleConfig();
        }
        onLoadFailed: error => {
            root._loaded = true;
            root._applyPersonalization();
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

    Component.onCompleted: mkStateDir.running = true
}
