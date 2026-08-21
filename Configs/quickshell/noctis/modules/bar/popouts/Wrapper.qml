import QtQuick
import qs.components
import qs.config
import qs.services

Item {
    id: root

    required property var screen
    required property int barWidth
    required property real windowWidth
    property bool hasCurrent: false
    property string currentName: ""
    property real currentCenter: 0
    property var currentTrayItem: null
    // Set while the mouse is over the flyout itself, so BarWrapper's
    // bar-hover-exit handler knows not to close a popout the user has
    // actually moved into to interact with (e.g. clicking a settings
    // toggle or dragging the media seek bar) -- the flyout draws outside
    // the bar's own hover-tracked area, so leaving the bar to reach it
    // would otherwise look identical to "mouse left, dismiss".
    readonly property bool hoveringFlyout: flyoutHover.hovered

    readonly property string category: currentName.startsWith("traymenu") ? "tray" : currentName

    // Keeps the loader (and thus popout content) alive through the
    // fade-out animation below -- deactivating it the instant hasCurrent
    // goes false would collapse width/height to 0 immediately and cut the
    // fade short instead of shrinking smoothly.
    property bool showContent: root.hasCurrent
    onHasCurrentChanged: {
        if (hasCurrent)
            showContent = true;
        else
            closeTimer.start();
    }

    Timer {
        id: closeTimer
        interval: Tokens.anim.durations.large
        onTriggered: root.showContent = false
    }

    StyledRect {
        id: flyout

        visible: opacity > 0
        opacity: root.hasCurrent && loader.item ? 1 : 0
        scale: opacity
        // Left-docked: strip sits at local x in [0, barWidth] (root shares
        // BarWindow's origin, which is the screen edge in that mode), so
        // the flyout starts just past it. Right-docked: the screen edge is
        // at local x = windowWidth instead, so the strip sits in
        // [windowWidth - barWidth, windowWidth] and the flyout must render
        // on the other side of it, ending at windowWidth - barWidth -
        // spacing and growing further left (hence the transformOrigin
        // flip, so the scale-in animation still expands away from the
        // strip instead of away from the flyout's own top-left corner).
        transformOrigin: Settings.barPositionRight ? Item.Right : Item.Left
        x: Settings.barPositionRight ? root.windowWidth - root.barWidth - Tokens.spacing.small - width : root.barWidth + Tokens.spacing.small
        // Clamp both edges -- the previous Math.max-only clamp kept the
        // flyout from starting above the screen top but let it run off
        // the bottom uncorrected for any popout tall enough that its
        // vertical center sits in the lower half of the bar (Settings,
        // Resources), since this window's own height matches the
        // screen's and content can't render past that boundary.
        y: Math.min(Math.max(0, root.currentCenter - height / 2), root.screen.height - height)
        width: loader.item ? loader.item.implicitWidth + Tokens.padding.medium * 2 : 0
        height: loader.item ? loader.item.implicitHeight + Tokens.padding.medium * 2 : 0
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainerHigh

        Behavior on opacity {
            Anim {
                type: Anim.Emphasized
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.Emphasized
            }
        }

        HoverHandler {
            id: flyoutHover
            onHoveredChanged: {
                if (!hovered)
                    root.hasCurrent = false;
            }
        }

        Loader {
            id: loader

            anchors.centerIn: parent
            active: root.showContent

            sourceComponent: {
                switch (root.category) {
                case "audio":
                    return audioComp;
                case "network":
                    return networkComp;
                case "bluetooth":
                    return bluetoothComp;
                case "battery":
                    return batteryComp;
                case "resources":
                    return resourcesComp;
                case "activewindow":
                    return windowComp;
                case "kblayout":
                    return kbLayoutComp;
                case "lockstatus":
                    return lockStatusComp;
                case "media":
                    return mediaComp;
                case "settings":
                    return settingsComp;
                case "tray":
                    return trayComp;
                default:
                    return null;
                }
            }
        }
    }

    Component {
        id: audioComp
        AudioPopout {}
    }
    Component {
        id: networkComp
        NetworkPopout {}
    }
    Component {
        id: bluetoothComp
        BluetoothPopout {}
    }
    Component {
        id: batteryComp
        BatteryPopout {}
    }
    Component {
        id: resourcesComp
        ResourcesPopout {}
    }
    Component {
        id: windowComp
        WindowPopout {}
    }
    Component {
        id: kbLayoutComp
        KbLayoutPopout {}
    }
    Component {
        id: lockStatusComp
        LockStatusPopout {}
    }
    Component {
        id: mediaComp
        MediaPopout {}
    }
    Component {
        id: settingsComp
        SettingsPopout {}
    }
    Component {
        id: trayComp
        TrayPopout {
            trayItem: root.currentTrayItem
        }
    }
}
