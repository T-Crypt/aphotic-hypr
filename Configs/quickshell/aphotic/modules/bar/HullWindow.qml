pragma ComponentBehavior: Bound

import "hull"
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services
import qs.utils

// The hull frame: one static fullscreen layer per screen that draws the
// ring around the desktop, its four corner zones and the two shelf rails.
// The top lane is the regular bar window and the bottom lane the regular
// dock window; this window only draws what joins them.
PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    required property ScreenState screenState

    readonly property bool active: Settings.barStyle === "hull" && !Strings.testRegexList(Config.bar.excludedScreens, root.screen.name)
    readonly property bool hasFullscreen: Hypr.monitorFor(root.screen)?.activeWorkspace?.lastIpcObject?.hasfullscreen === true
    readonly property bool ringShown: root.active && !SessionLockState.locked && (!root.hasFullscreen || Config.hull.overFullscreen)
    readonly property bool lanesLive: root.ringShown && !root.hasFullscreen

    readonly property int band: Config.hull.ring
    readonly property int reach: Math.max(Config.hull.ring, Config.hull.edgeReach)
    readonly property int zone: Config.hull.cornerZone
    readonly property int radius: Config.border.rounding
    readonly property int barThickness: Settings.barInnerWidth + Math.max(Tokens.padding.small, Config.border.thickness) * 2
    readonly property int topInset: Settings.barVisibility === "always" || root.screenState.bar ? root.barThickness : root.band
    readonly property string output: root.screen?.name ?? ""

    readonly property int agentSessions: AgentProviders.providers.reduce((n, p) => n + AgentProviders.sessionCountOf(p.id ?? ""), 0)

    WlrLayershell.namespace: "aphotic-hull"
    WlrLayershell.layer: root.hasFullscreen && Config.hull.overFullscreen ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    visible: root.active

    // Only drawn chrome takes input: the two shelf rails, the corner zones
    // and whichever flyout is open. The rest of the screen passes through.
    mask: Region {
        Region {
            x: 0
            y: root.topInset
            width: root.lanesLive && Config.hull.shelfRails ? root.reach : 0
            height: root.height - root.topInset
        }
        Region {
            x: root.width - root.reach
            y: root.topInset
            width: root.lanesLive && Config.hull.shelfRails ? root.reach : 0
            height: root.height - root.topInset
        }
        Region {
            item: root.lanesLive ? agents.zoneItem : null
        }
        Region {
            item: root.lanesLive ? alerts.zoneItem : null
        }
        Region {
            item: root.lanesLive ? session.zoneItem : null
        }
        Region {
            item: root.lanesLive ? machine.zoneItem : null
        }
        Region {
            item: agents.open ? agents.cardItem : null
        }
        Region {
            item: alerts.open ? alerts.cardItem : null
        }
        Region {
            item: session.open ? session.cardItem : null
        }
        Region {
            item: machine.open ? machine.cardItem : null
        }
    }

    Item {
        id: frame

        anchors.fill: parent
        opacity: root.ringShown ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Rectangle {
            width: root.zone
            height: root.topInset
            color: Colours.signalStyle.bar

            SignalLine {
                edge: "end"
            }
        }

        Rectangle {
            x: root.width - width
            width: root.zone
            height: root.topInset
            color: Colours.signalStyle.bar

            SignalLine {
                edge: "end"
            }
        }

        Rectangle {
            id: leftBand

            y: root.topInset
            width: root.band
            height: root.height - root.topInset
            color: Colours.signalStyle.bar

            SignalLine {
                horizontal: false
                edge: "end"
                level: Shelves.isOpen(root.output, "left") ? "active" : "idle"
                hoverStart: leftRail.pointerY - 36
                hoverLength: 72
                hoverVisible: leftRail.hovered && leftRail.enabled
            }
        }

        Rectangle {
            id: rightBand

            x: root.width - root.band
            y: root.topInset
            width: root.band
            height: root.height - root.topInset
            color: Colours.signalStyle.bar

            SignalLine {
                horizontal: false
                edge: "start"
                level: Shelves.isOpen(root.output, "right") ? "active" : "idle"
                hoverStart: rightRail.pointerY - 36
                hoverLength: 72
                hoverVisible: rightRail.hovered && rightRail.enabled
            }
        }

        Rectangle {
            y: root.height - root.band
            width: root.width
            height: root.band
            color: Colours.signalStyle.bar

            SignalLine {
                x: root.band
                width: parent.width - root.band * 2
                level: root.screenState.engaged ? "active" : "idle"
            }
        }

        ConcaveCorner {
            x: root.band
            y: root.topInset
            corner: 0
            radius: root.radius
            color: Colours.signalStyle.bar
            edgeColor: Colours.signalStyle.hairline
        }

        ConcaveCorner {
            x: root.width - root.band - root.radius
            y: root.topInset
            corner: 1
            radius: root.radius
            color: Colours.signalStyle.bar
            edgeColor: Colours.signalStyle.hairline
        }

        ConcaveCorner {
            x: root.band
            y: root.height - root.band - root.radius
            corner: 2
            radius: root.radius
            color: Colours.signalStyle.bar
            edgeColor: Colours.signalStyle.hairline
        }

        ConcaveCorner {
            x: root.width - root.band - root.radius
            y: root.height - root.band - root.radius
            corner: 3
            radius: root.radius
            color: Colours.signalStyle.bar
            edgeColor: Colours.signalStyle.hairline
        }

        HullSweep {
            id: sweep

            band: root.band
            topInset: root.topInset
        }

        ShelfRail {
            id: leftRail

            edge: "left"
            x: 0
        }

        ShelfRail {
            id: rightRail

            edge: "right"
            x: root.width - root.reach
        }

        HullCorner {
            id: agents

            corner: 0
            zoneWidth: root.zone
            zoneHeight: root.topInset
            enabled: root.lanesLive && AgentProviders.active
            level: root.agentSessions > 0 ? "active" : "idle"
            title: qsTr("Agents")
            detail: root.agentSessions === 0 ? qsTr("No live sessions") : qsTr("%n live session(s)", "", root.agentSessions)
            actions: [
                {
                    icon: "smart_toy",
                    label: qsTr("Agent panel"),
                    on: root.screenState.agentPanel,
                    run: () => root.screenState.agentPanel = !root.screenState.agentPanel
                },
                {
                    icon: "insights",
                    label: qsTr("Intelligence"),
                    on: root.screenState.intelligence,
                    run: () => root.screenState.intelligence = !root.screenState.intelligence
                }
            ]
        }

        HullCorner {
            id: alerts

            corner: 1
            zoneWidth: root.zone
            zoneHeight: root.topInset
            enabled: root.lanesLive
            level: DoNotDisturb.enabled ? "idle" : NotificationHistory.unreadCount > 0 ? "active" : "idle"
            title: qsTr("Notifications")
            detail: (NotificationHistory.unreadCount === 0 ? qsTr("Nothing unread") : qsTr("%n unread", "", NotificationHistory.unreadCount)) + (DoNotDisturb.enabled ? qsTr(", do not disturb is on") : "")
            actions: [
                {
                    icon: "notifications",
                    label: qsTr("Notification center"),
                    on: root.screenState.notificationCenter,
                    run: () => root.screenState.notificationCenter = !root.screenState.notificationCenter
                },
                {
                    icon: DoNotDisturb.enabled ? "notifications_off" : "do_not_disturb_on",
                    label: qsTr("Do not disturb"),
                    on: DoNotDisturb.enabled,
                    run: () => DoNotDisturb.toggle()
                }
            ]
        }

        HullCorner {
            id: session

            corner: 2
            zoneWidth: root.zone
            zoneHeight: root.zone
            enabled: root.lanesLive
            level: DoNotDisturb.pomodoroFocusActive ? "active" : "idle"
            title: qsTr("Session")
            detail: Time.format("dddd d MMMM")
            actions: [
                {
                    icon: "lock",
                    label: qsTr("Lock"),
                    on: false,
                    run: () => Quickshell.execDetached(["qs", "-c", "aphotic", "ipc", "call", "lock", "engage"])
                },
                {
                    icon: "wallpaper",
                    label: qsTr("Wallpaper"),
                    on: root.screenState.wallpaperPicker,
                    run: () => root.screenState.wallpaperPicker = !root.screenState.wallpaperPicker
                },
                {
                    icon: "power_settings_new",
                    label: qsTr("Power"),
                    on: root.screenState.session,
                    run: () => root.screenState.session = !root.screenState.session
                }
            ]
        }

        HullCorner {
            id: machine

            corner: 3
            zoneWidth: root.zone
            zoneHeight: root.zone
            enabled: root.lanesLive
            level: ResourcePosture.surfaced ? "warn" : "idle"
            title: qsTr("Machine")
            detail: ResourcePosture.headline || qsTr("Nothing needs attention")
            actions: [
                {
                    icon: "dashboard",
                    label: qsTr("Dashboard"),
                    on: root.screenState.dashboard,
                    run: () => root.screenState.dashboard = !root.screenState.dashboard
                },
                {
                    icon: "settings",
                    label: qsTr("Settings"),
                    on: root.screenState.settings,
                    run: () => root.screenState.settings = !root.screenState.settings
                }
            ]
        }
    }

    Connections {
        target: Surfaces

        function onChanged(screenState: var, name: string, open: bool): void {
            if (screenState === root.screenState && root.lanesLive)
                sweep.run();
        }
    }

    component ShelfRail: Item {
        id: rail

        required property string edge
        readonly property bool hovered: railHover.hovered
        readonly property real pointerY: railHover.point.position.y

        y: root.topInset
        width: root.reach
        height: root.height - root.topInset
        enabled: root.lanesLive && Config.hull.shelfRails && (Shelves.config(root.output)[rail.edge]?.enabled ?? false)

        HoverHandler {
            id: railHover
        }

        TapHandler {
            onTapped: Shelves.toggle(root.output, rail.edge)
        }
    }
}
