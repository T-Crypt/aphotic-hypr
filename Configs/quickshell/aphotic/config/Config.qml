pragma Singleton
import QtQuick
import Quickshell
import qs.config

// bar.* defaults below match the reference plugin's own defaults
// except where noted — this repo has no config file/UI yet to
// override these, so matching upstream's own defaults is the safer
// choice absent a stated Aphotic-specific preference. border.* keeps
// this repo's original (smaller) values from Task 2 rather than
// upstream's 10/2/25 — no border is actually rendered anywhere yet to
// visually justify swapping it; revisit when Task 7 wires BarWindow.qml.
QtObject {
    readonly property QtObject border: QtObject {
        readonly property int thickness: 2
        readonly property int minThickness: 1
        readonly property int rounding: 12
    }

    readonly property QtObject bar: QtObject {
        readonly property bool persistent: true
        readonly property bool showOnHover: true
        readonly property int dragThreshold: 20
        readonly property var excludedScreens: []

        readonly property QtObject tray: QtObject {
            readonly property bool background: true
            readonly property bool recolour: false
            readonly property bool compact: false
            readonly property var iconSubs: GlobalConfig.bar.tray.iconSubs
            readonly property var hiddenIcons: GlobalConfig.bar.tray.hiddenIcons
        }

        readonly property QtObject clock: QtObject {
            readonly property bool background: true
            readonly property bool showDate: false
            readonly property bool showIcon: true
        }

        readonly property QtObject popouts: QtObject {
            readonly property bool statusIcons: true
            readonly property bool tray: true
            readonly property bool activeWindow: true
            readonly property bool media: true
            readonly property bool settings: true
        }

        readonly property QtObject activeWindow: QtObject {
            readonly property bool compact: false
            readonly property bool inverted: false
            readonly property bool showOnHover: true
        }

        readonly property QtObject scrollActions: QtObject {
            readonly property bool workspaces: true
            readonly property bool volume: true
            readonly property bool brightness: true
        }

        readonly property QtObject workspaces: QtObject {
            readonly property int shown: 5
            readonly property bool activeIndicator: true
            readonly property bool occupiedBg: false
            readonly property bool showWindows: true
            readonly property bool showWindowsOnSpecialWorkspaces: true
            readonly property int maxWindowIcons: 5
            readonly property bool activeTrail: false
            readonly property bool perMonitorWorkspaces: GlobalConfig.bar.workspaces.perMonitorWorkspaces
            readonly property string label: "  "
            readonly property string occupiedLabel: "󰮯"
            readonly property string activeLabel: "󰮯"
            readonly property string capitalisation: "preserve"
            readonly property var specialWorkspaceIcons: GlobalConfig.bar.workspaces.specialWorkspaceIcons
            readonly property var windowIcons: GlobalConfig.bar.workspaces.windowIcons
        }

        readonly property QtObject statusIcons: QtObject {
            // Grouped by function with a thin divider between clusters --
            // Connectivity (Wi-Fi/Bluetooth/VPN/host info), System (lock
            // state, CPU+mem+disk, network throughput, Pomodoro timer,
            // battery/power profile), Notifications (DND, history center).
            // audio/microphone/kbLayout stay disabled by default (opt-in,
            // not part of any named group).
            readonly property var values: [
                { id: "audio", enabled: false },
                { id: "microphone", enabled: false },
                { id: "kbLayout", enabled: false },
                { id: "network", enabled: true },
                { id: "bluetooth", enabled: true },
                { id: "vpn", enabled: true },
                { id: "hostInfo", enabled: true },
                { id: "groupDivider", enabled: true },
                { id: "lockStatus", enabled: true },
                { id: "resources", enabled: true },
                { id: "networkSpeed", enabled: true },
                { id: "pomodoro", enabled: true },
                { id: "battery", enabled: true },
                { id: "groupDivider", enabled: true },
                { id: "dnd", enabled: true },
                { id: "notifCenter", enabled: true }
            ]
        }

        // Capsule style. expanded*/stacked* also bound the STATIC
        // layer-shell surface the capsule draws into (see
        // modules/bar/CapsuleWindow.qml) -- content wanting more than
        // this is clipped by the compositor rather than growing the
        // window, so a richer expanded surface raises these, not just its
        // own size. expanded* is the top/bottom-docked shape, stacked*
        // the left/right-docked one.
        readonly property QtObject capsule: QtObject {
            // The pill's own length floor. Its real length follows its
            // content, but never drops below this, so a sparse bar is still
            // a bar rather than a nub.
            readonly property int minLength: 420
            // The media popout, drawn as its own surface below (or above,
            // or beside) the pill so the pill itself stays a working bar
            // the whole time it is open. popout* is the top/bottom-docked
            // shape, stackedPopout* the left/right-docked one.
            readonly property int popoutWidth: 440
            readonly property int popoutHeight: 136
            readonly property int stackedPopoutWidth: 268
            readonly property int stackedPopoutHeight: 330
            // Visual gap between pill and popout. The two items stay FLUSH
            // (the gap is transparent padding inside the popout's own
            // bounds) so the pointer never crosses a dead zone travelling
            // between them -- the same trap modules/bar/popouts/Wrapper.qml
            // documents at length.
            readonly property int gap: 8
            readonly property int edgeMargin: 8
            // Sliver left on screen by auto-hide, so there is something to
            // aim at and something to see.
            readonly property int peek: 6
        }

        readonly property QtObject entries: QtObject {
            readonly property var values: [
                { id: "logo", enabled: true },
                { id: "workspaces", enabled: true },
                { id: "spacer", enabled: true },
                { id: "activeWindow", enabled: true },
                { id: "spacer", enabled: true },
                { id: "media", enabled: true },
                { id: "tray", enabled: true },
                { id: "clock", enabled: true },
                { id: "agent", enabled: true },
                { id: "statusIcons", enabled: true },
                { id: "gap", enabled: true },
                { id: "settings", enabled: true },
                { id: "power", enabled: true }
            ]
        }
    }

    readonly property QtObject services: QtObject {
        readonly property real brightnessIncrement: GlobalConfig.services.brightnessIncrement
        readonly property bool useTwelveHourClock: GlobalConfig.services.useTwelveHourClock
        readonly property bool useFahrenheitPerformance: false
    }

    // Matches the reference plugin's own OsdConfig defaults.
    readonly property QtObject osd: QtObject {
        readonly property bool enabled: true
        readonly property int hideDelay: 2000
        readonly property bool enableBrightness: true
        readonly property bool enableMicrophone: false
    }

    // Merged from the standalone BackgroundConfig.qml/DashboardConfig.qml
    // (Quickshell.Io JsonObject files) into this repo's one real config
    // singleton, so there's a single config surface instead of two.
    readonly property QtObject background: QtObject {
        readonly property bool enabled: true
        readonly property bool wallpaperEnabled: true

        readonly property QtObject desktopClock: QtObject {
            readonly property bool enabled: false
            readonly property real scale: 1.0
            readonly property string position: "bottom-right"
            readonly property bool invertColors: false

            readonly property QtObject background: QtObject {
                readonly property bool enabled: false
                readonly property real opacity: 0.7
                readonly property bool blur: true
            }

            readonly property QtObject shadow: QtObject {
                readonly property bool enabled: true
                readonly property real opacity: 0.7
                readonly property real blur: 0.4
            }
        }
    }

    readonly property QtObject dashboard: QtObject {
        readonly property bool enabled: true
        readonly property int resourceUpdateInterval: 2000
        readonly property int detailUpdateInterval: 30000
        // What a surface asking for fast GPU sampling gets instead. Only
        // the GPU poll moves -- CPU temperature genuinely does not need
        // this, and `sensors -j` costs more per call than nvidia-smi's
        // utilisation query does (42ms vs 26ms, measured).
        readonly property int detailFastUpdateInterval: 2000

        readonly property QtObject performance: QtObject {
            readonly property bool showBattery: true
            readonly property bool showGpu: true
            readonly property bool showCpu: true
            readonly property bool showMemory: true
            readonly property bool showStorage: true
            readonly property bool showNetwork: true
        }
    }

    readonly property QtObject notch: QtObject {
        readonly property bool enabled: true

        // Every size here is expressed against the bar's docked edge, not
        // against the screen: `collapsedWidth` runs ALONG that edge and
        // `collapsedHeight` is the strip's thickness, so a side-docked bar
        // gets a 26x132 strip from the same two numbers a top-docked one
        // gets 132x26 from. expandedWidth and maxHeight are the open
        // panel's screen-space width and height in every orientation --
        // the panel is the same rectangle wherever it opens from, only the
        // pinned edge changes.
        //
        // expandedWidth and maxHeight also bound the STATIC layer-shell
        // surface the notch draws into (see modules/notch/NotchWindow.qml).
        // Content wanting more than that is clipped by the compositor
        // rather than growing the window, so a new tile needing room
        // raises these, not just its own size.
        readonly property int collapsedWidth: 132
        readonly property int collapsedHeight: 26
        readonly property int expandedWidth: 420
        readonly property int maxHeight: 400

        // Slack around the panel inside that static surface: drop-shadow
        // bleed plus the open spring's overshoot, which reaches about 8%
        // of the travel past the target before it settles. Undersized, the
        // compositor clips the bounce and the shadow instead of the shell.
        readonly property int surfaceMargin: 40
        // How far the strip sits off the edge it docks against.
        readonly property int edgeGap: 4

        readonly property int processUpdateInterval: 1500
        readonly property int gpuUpdateInterval: 3000
        readonly property int processCount: 6
    }

    readonly property QtObject launcher: QtObject {
        readonly property string emojiListPath: `${Quickshell.env("HOME")}/.config/quickshell/aphotic/data/emoji.txt`
        readonly property string wallpaperDir: `${Quickshell.env("HOME")}/.config/awww`
    }
}
