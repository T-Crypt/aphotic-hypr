pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Runtime user-toggleable settings, persisted to
// ~/.local/state/noctis/settings.json (a sibling of theme.json, same
// FileView load/save pattern as services/Themes.qml) so the settings
// popout's toggles survive a shell restart instead of resetting to
// Config.qml's compile-time defaults every time.
Singleton {
    id: root

    readonly property string statePath: `${Quickshell.env("HOME")}/.local/state/noctis/settings.json`

    property bool twelveHourClock: GlobalConfig.services.useTwelveHourClock
    property bool showClockDate: Config.bar.clock.showDate
    property bool barPersistent: Config.bar.persistent
    property bool desktopClockEnabled: Config.background.desktopClock.enabled
    property bool barPositionRight: false
    property bool barCompact: false

    property bool osdEnabled: Config.osd.enabled
    property int osdHideDelay: Config.osd.hideDelay
    property bool osdEnableBrightness: Config.osd.enableBrightness
    property bool osdEnableMicrophone: Config.osd.enableMicrophone

    property real notifExpireTimeout: GlobalConfig.notifs.defaultExpireTimeout

    readonly property real barInnerWidth: Tokens.sizes.bar.innerWidth * (barCompact ? 0.85 : 1)

    property bool _loaded: false

    function _saveState(): void {
        if (!root._loaded)
            return;
        stateWriter.setText(JSON.stringify({
            twelveHourClock: root.twelveHourClock,
            showClockDate: root.showClockDate,
            barPersistent: root.barPersistent,
            desktopClockEnabled: root.desktopClockEnabled,
            barPositionRight: root.barPositionRight,
            barCompact: root.barCompact,
            osdEnabled: root.osdEnabled,
            osdHideDelay: root.osdHideDelay,
            osdEnableBrightness: root.osdEnableBrightness,
            osdEnableMicrophone: root.osdEnableMicrophone,
            notifExpireTimeout: root.notifExpireTimeout
        }, null, 2));
    }

    onTwelveHourClockChanged: root._saveState()
    onShowClockDateChanged: root._saveState()
    onBarPersistentChanged: root._saveState()
    onDesktopClockEnabledChanged: root._saveState()
    onBarPositionRightChanged: root._saveState()
    onBarCompactChanged: root._saveState()
    onOsdEnabledChanged: root._saveState()
    onOsdHideDelayChanged: root._saveState()
    onOsdEnableBrightnessChanged: root._saveState()
    onOsdEnableMicrophoneChanged: root._saveState()
    onNotifExpireTimeoutChanged: root._saveState()

    FileView {
        id: stateFile

        path: root.statePath
        watchChanges: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (typeof data.twelveHourClock === "boolean")
                    root.twelveHourClock = data.twelveHourClock;
                if (typeof data.showClockDate === "boolean")
                    root.showClockDate = data.showClockDate;
                if (typeof data.barPersistent === "boolean")
                    root.barPersistent = data.barPersistent;
                if (typeof data.desktopClockEnabled === "boolean")
                    root.desktopClockEnabled = data.desktopClockEnabled;
                if (typeof data.barPositionRight === "boolean")
                    root.barPositionRight = data.barPositionRight;
                if (typeof data.barCompact === "boolean")
                    root.barCompact = data.barCompact;
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
            } catch (e) {
                // No state file yet, or malformed -- keep the Config.qml/
                // GlobalConfig.qml defaults already set above.
            }
            root._loaded = true;
        }
        onLoadFailed: error => {
            root._loaded = true;
        }
    }

    FileView {
        id: stateWriter

        path: root.statePath
        printErrors: false
    }

    Process {
        id: mkStateDir
        command: ["mkdir", "-p", `${Quickshell.env("HOME")}/.local/state/noctis`]
        onExited: stateFile.reload()
    }

    Component.onCompleted: mkStateDir.running = true
}
