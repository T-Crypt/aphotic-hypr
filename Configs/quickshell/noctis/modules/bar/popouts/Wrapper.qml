import QtQuick
import QtQuick.Effects
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
        // Left-docked: strip sits at local x in [0, barWidth] (root shares
        // BarWindow's origin, which is the screen edge in that mode), so
        // the flyout starts just past it. Right-docked: the screen edge is
        // at local x = windowWidth instead, so the strip sits in
        // [windowWidth - barWidth, windowWidth] and the flyout must render
        // on the other side of it, ending at windowWidth - barWidth -
        // spacing and growing further left. x is a plain expression of
        // width here (not scale/transformOrigin), so the Behavior on
        // width below drags x along with it every frame, keeping the
        // flyout's edge nearest the bar pinned in both docking modes as
        // it grows/shrinks, rather than growing away from a fixed corner.
        x: Settings.barPositionRight ? root.windowWidth - root.barWidth - Tokens.spacing.small - width : root.barWidth + Tokens.spacing.small
        // Clamp both edges -- Math.max alone kept the flyout from starting
        // above the screen top but let it run off the bottom uncorrected
        // for any popout tall enough that its vertical center sits in the
        // lower half of the bar (Settings, Resources), since this
        // window's own height matches the screen's and content can't
        // render past that boundary.
        y: Math.min(Math.max(0, root.currentCenter - height / 2), root.screen.height - height)
        width: loader.item ? loader.item.implicitWidth + Tokens.padding.medium * 2 : 0
        height: loader.item ? loader.item.implicitHeight + Tokens.padding.medium * 2 : 0
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainerHigh

        // Real geometry morph instead of a scale trick -- x/y/width/height
        // all animate on the same emphasized (fast-start, no-overshoot)
        // curve already used for opacity, so open/close/resize (switching
        // between popouts of different sizes while one is already open)
        // reads as one continuous shape change instead of an instant
        // snap-then-fade. y depends on height and x depends on width, so
        // those two ride along with the resize automatically -- the
        // flyout grows/shrinks around its anchor point and keeps its
        // near-bar edge pinned, rather than just stretching from a corner.
        Behavior on x {
            Anim { type: Anim.Emphasized }
        }
        Behavior on y {
            Anim { type: Anim.Emphasized }
        }
        Behavior on width {
            Anim { type: Anim.Emphasized }
        }
        Behavior on height {
            Anim { type: Anim.Emphasized }
        }
        Behavior on radius {
            Anim { type: Anim.Emphasized }
        }
        Behavior on opacity {
            Anim { type: Anim.Emphasized }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: 0.5
            shadowBlur: 0.5
            shadowVerticalOffset: 2
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
            // Staggered behind the container: opacity multiplies with
            // flyout's own opacity above, so content only becomes fully
            // visible once both have finished, but on entry it visibly
            // starts a beat after the container begins its morph (no
            // delay on close, so content doesn't linger while the
            // container is already shrinking) -- that stagger is what
            // reads as the container "arriving first" rather than
            // everything popping in at once.
            opacity: root.hasCurrent ? 1 : 0

            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: root.hasCurrent ? 70 : 0 }
                    Anim { type: Anim.DefaultEffects }
                }
            }

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
