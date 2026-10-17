import QtQuick
import QtQuick.Shapes
import qs.components
import qs.config
import qs.services

Item {
    id: root

    required property var screen
    required property int barWidth
    required property real windowWidth
    required property real windowHeight
    required property ScreenState screenState
    readonly property alias flyoutItem: flyout
    readonly property alias agentFlyoutItem: agentFlyout
    property bool hasCurrent: false
    property string currentName: ""
    property real currentCenter: 0
    property var currentTrayItem: null
    property var currentTaskGroup: null
    // The agent icon's own along-axis center, kept live by whichever bar
    // style actually has an "agent" entry via a continuous binding --
    // separate from currentCenter, which tracks whatever's hovered. The
    // agent popout opens on a click and has to stay anchored to the
    // agent icon's own fixed position regardless of what the mouse does
    // afterward.
    property real agentCenter: 0
    // Set while the mouse is over the flyout itself, so BarWrapper's
    // bar-hover-exit handler knows not to close a popout the user has
    // moved into to interact with (clicking a settings toggle, dragging
    // the media seek bar) -- the flyout draws outside the bar's own
    // hover-tracked area, so leaving the bar to reach it would otherwise
    // look identical to "mouse left, dismiss".
    //
    // This used to read `flyoutHover.hovered`, which MouseArea does not
    // have -- only `containsMouse`. The reference evaluated to undefined
    // (falsy) always, so `hoveringFlyout` was permanently false and the
    // bar's hover-exit closed the popout the instant the cursor left the
    // strip, on every crossing, in every orientation. `containsMouse` is
    // the real property.
    readonly property bool hoveringFlyout: flyoutHover.containsMouse

    readonly property string category: currentName.startsWith("traymenu") ? "tray" : currentName

    // Along-axis anchor radius used below to keep the flyout's near edge
    // pinned to roughly the hovered icon's own edge, regardless of which
    // popout is open -- a fixed reference (the bar's own icon-strip
    // thickness), not the popout's own width/height. Both axes used to
    // center the flyout on the icon using the popout's own along-axis
    // dimension, so switching between two popouts of different sizes
    // re-centered around a different point each time -- the icon never
    // moved, but the flyout's near edge visibly jumped every time.
    // With this fixed radius only the far edge moves as content size
    // changes; the near edge (and the bar itself) stays put.
    readonly property real alongAxisAnchorRadius: Settings.barInnerWidth / 2

    // The flyout's own width/height (below) are Behavior-animated whenever
    // the popout content changes size, which made x/y chase a moving
    // target: the clamp/anchor expressions read `width`/`height`
    // directly, so every frame of the resize animation fed a slightly
    // different value back into the position formula, compounding a
    // wobble on top of the x/y animation's own move. Reading the loader's
    // raw, un-animated implicitWidth/implicitHeight for position math
    // instead keeps x/y animating toward a stable final target from the
    // first frame.
    readonly property real nonAnimWidth: loader.item ? loader.item.implicitWidth + Tokens.padding.medium * 2 : 0
    readonly property real nonAnimHeight: loader.item ? loader.item.implicitHeight + Tokens.padding.medium * 2 : 0
    readonly property real agentNonAnimWidth: agentLoader.item ? agentLoader.item.implicitWidth + Tokens.padding.medium * 2 : 0
    readonly property real agentNonAnimHeight: agentLoader.item ? agentLoader.item.implicitHeight + Tokens.padding.medium * 2 : 0

    // Left/right-docked (vertical bar, see Settings.barHorizontal): the
    // strip sits at local x in [0, barWidth] (root shares BarWindow's
    // origin, the screen edge in that mode) when docked left, so the
    // flyout starts flush against it. Right-docked: the screen edge is at
    // local x = windowWidth instead, so the strip sits in
    // [windowWidth - barWidth, windowWidth] and the flyout renders on the
    // other side of it, ending at windowWidth - barWidth and growing
    // further left. Top/bottom-docked mirrors the same reasoning onto
    // y/windowHeight.
    //
    // The gap is zero on purpose, not for looks: BarWindow.qml's input
    // mask only ever covers the bar's bounds and the flyout's own rect,
    // so any real gap between the bar's hover-tracked area and the
    // flyout's own is an un-hoverable dead zone. Zero gap leaves no dead
    // zone to fall into. bridgeItem below is now dead weight kept only
    // until it's confirmed unneeded and removed.
    readonly property real flyoutX: Settings.barHorizontal ? Math.min(Math.max(0, root.currentCenter - root.alongAxisAnchorRadius), (root.screen?.width ?? 0) - root.nonAnimWidth) : (Settings.barPositionRight ? root.windowWidth - root.barWidth - root.nonAnimWidth : root.barWidth)
    // Clamp the along-axis edge: Math.max alone kept the flyout from
    // starting before the screen's near edge but let it run off the far
    // edge for any popout whose along-axis center sits in the latter half
    // of the bar, since this window's own size matches the screen's on
    // that axis and content can't render past that boundary.
    readonly property real flyoutY: Settings.barHorizontal ? (Settings.barPositionBottom ? root.windowHeight - root.barWidth - root.nonAnimHeight : root.barWidth) : Math.min(Math.max(0, root.currentCenter - root.alongAxisAnchorRadius), (root.screen?.height ?? 0) - root.nonAnimHeight)
    readonly property real agentFlyoutX: Settings.barHorizontal ? Math.min(Math.max(0, root.agentCenter - root.alongAxisAnchorRadius), (root.screen?.width ?? 0) - root.agentNonAnimWidth) : (Settings.barPositionRight ? root.windowWidth - root.barWidth - root.agentNonAnimWidth : root.barWidth)
    readonly property real agentFlyoutY: Settings.barHorizontal ? (Settings.barPositionBottom ? root.windowHeight - root.barWidth - root.agentNonAnimHeight : root.barWidth) : Math.min(Math.max(0, root.agentCenter - root.alongAxisAnchorRadius), (root.screen?.height ?? 0) - root.agentNonAnimHeight)
    // Wing side flush against the screen edge has nowhere to draw, so the
    // corner fillet on that side is hidden while the clamp holds.
    readonly property bool flyoutNearClamped: Settings.barHorizontal ? root.flyoutX <= 0 : root.flyoutY <= 0
    readonly property bool flyoutFarClamped: Settings.barHorizontal ? (root.currentCenter - root.alongAxisAnchorRadius) >= ((root.screen?.width ?? 0) - root.nonAnimWidth) : (root.currentCenter - root.alongAxisAnchorRadius) >= ((root.screen?.height ?? 0) - root.nonAnimHeight)
    readonly property bool agentNearClamped: Settings.barHorizontal ? root.agentFlyoutX <= 0 : root.agentFlyoutY <= 0
    readonly property bool agentFarClamped: Settings.barHorizontal ? (root.agentCenter - root.alongAxisAnchorRadius) >= ((root.screen?.width ?? 0) - root.agentNonAnimWidth) : (root.agentCenter - root.alongAxisAnchorRadius) >= ((root.screen?.height ?? 0) - root.agentNonAnimHeight)

    // Keeps the loader (and thus popout content) alive through the
    // fade-out animation below -- deactivating it the instant hasCurrent
    // goes false would collapse width/height to 0 immediately and cut the
    // fade short instead of shrinking smoothly.
    property bool showContent: root.hasCurrent
    // true only while the close fade runs; the "hidden" state (scale
    // 0.94) is what a fresh open grows out of, and the snap back to it
    // happens invisibly once the fade is done.
    property bool flyoutClosing: false
    property bool agentShowContent: root.screenState?.agentPanel ?? false
    property bool agentClosing: false
    // Outgoing currentCenter, captured while it is still the OLD value:
    // the bar's hover handlers assign currentName before currentCenter,
    // so the slide direction of a popout switch can only be resolved once
    // the new center lands. NaN means "no switch in flight".
    property real pendingSwitchCenter: NaN
    property real switchSign: 1

    onHasCurrentChanged: {
        if (hasCurrent) {
            showContent = true;
            flyoutClosing = false;
            // A pending close from a same-frame hover blip must not fire
            // after a revive (see flyoutHover below) and empty the loader
            // out from under a popout that's still open.
            closeTimer.stop();
        } else {
            flyoutClosing = true;
            closeTimer.start();
        }
    }

    onCurrentNameChanged: {
        if (hasCurrent)
            pendingSwitchCenter = currentCenter;
    }

    onCurrentCenterChanged: {
        if (Number.isNaN(pendingSwitchCenter))
            return;
        const delta = currentCenter - pendingSwitchCenter;
        pendingSwitchCenter = NaN;
        if (!hasCurrent)
            return;
        switchSign = delta < 0 ? -1 : 1;
        slideHost.opacity = 0;
        slideHost.x = Settings.barHorizontal ? Tokens.spacing.small * switchSign : 0;
        slideHost.y = Settings.barHorizontal ? 0 : Tokens.spacing.small * switchSign;
        switchIn.start();
    }

    Connections {
        target: root.screenState
        function onAgentPanelChanged(): void {
            if (root.screenState.agentPanel) {
                root.agentShowContent = true;
                root.agentClosing = false;
                agentCloseTimer.stop();
            } else {
                root.agentClosing = true;
                agentCloseTimer.start();
            }
        }
    }

    Timer {
        id: closeTimer
        interval: Tokens.anim.durations.normal
        onTriggered: {
            root.showContent = false
            root.flyoutClosing = false
        }
    }

    Timer {
        id: agentCloseTimer
        interval: Tokens.anim.durations.normal
        onTriggered: {
            root.agentShowContent = false
            root.agentClosing = false
        }
    }

    // Incoming-content settle for a popout switch while one is already
    // open: the old item is gone by the time this runs (Loader swaps
    // synchronously), so the new one fades in from the offset the switch
    // handler set on it.
    ParallelAnimation {
        id: switchIn

        Anim {
            type: Anim.DefaultEffects
            target: slideHost
            properties: "opacity"
            to: 1
        }
        Anim {
            type: Anim.Emphasized
            target: slideHost
            properties: "x,y"
            to: 0
        }
    }

    Item {
        id: flyoutWrap

        // x/y are plain expressions of width/height here (not
        // scale/transformOrigin), so the Behaviors on width/height below
        // drag x/y along with them every frame, keeping the flyout's edge
        // nearest the bar pinned in every docking mode as it grows and
        // shrinks. Width, height, x and y all animate on the same
        // emphasized curve, so open, close and resize (switching between
        // popouts of different sizes while one is already open) read as
        // one continuous shape change instead of an instant snap.
        x: root.flyoutX
        y: root.flyoutY
        width: root.nonAnimWidth
        height: root.nonAnimHeight

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

        // Bar-side edge center: the entrance scale grows/shrinks toward
        // the bar, not the flyout's own center.
        transformOrigin: Settings.barHorizontal ? (Settings.barPositionBottom ? Item.Bottom : Item.Top) : (Settings.barPositionRight ? Item.Right : Item.Left)
        state: root.hasCurrent ? "open" : (root.flyoutClosing ? "closing" : "hidden")
        states: [
            State {
                name: "open"
                PropertyChanges { target: flyoutWrap; scale: 1.0; opacity: 1.0 }
            },
            State {
                name: "closing"
                PropertyChanges { target: flyoutWrap; scale: 0.96; opacity: 0.0 }
            },
            State {
                name: "hidden"
                PropertyChanges { target: flyoutWrap; scale: 0.94; opacity: 0.0 }
            }
        ]
        Behavior on scale {
            Anim { type: root.hasCurrent ? Anim.Emphasized : Anim.EmphasizedSmall }
            enabled: root.hasCurrent || root.flyoutClosing
        }
        Behavior on opacity {
            Anim { type: root.hasCurrent ? Anim.DefaultEffects : Anim.FastEffects }
            enabled: root.hasCurrent || root.flyoutClosing
        }

        Elevation {
            target: flyout
            level: 2
            topLeftRadius: flyout.topLeftRadius
            topRightRadius: flyout.topRightRadius
            bottomLeftRadius: flyout.bottomLeftRadius
            bottomRightRadius: flyout.bottomRightRadius
        }

        // Concave fillets just outside the flyout's bar-side corners, so its
        // side edges curve into the bar edge.
        ConcaveCorner {
            id: flyoutWingStart

            radius: Tokens.rounding.medium
            color: flyout.color
            edgeColor: Colours.signalStyle.hairline
            corner: Settings.barHorizontal ? (Settings.barPositionBottom ? 2 : 0) : (Settings.barPositionRight ? 2 : 3)
            x: Settings.barHorizontal ? -radius : (Settings.barPositionRight ? parent.width - radius : 0)
            y: Settings.barHorizontal ? (Settings.barPositionBottom ? parent.height - radius : 0) : -radius
            visible: !root.flyoutNearClamped && parent.opacity > 0
        }
        ConcaveCorner {
            id: flyoutWingEnd

            radius: Tokens.rounding.medium
            color: flyout.color
            edgeColor: Colours.signalStyle.hairline
            corner: Settings.barHorizontal ? (Settings.barPositionBottom ? 3 : 1) : (Settings.barPositionRight ? 0 : 1)
            x: Settings.barHorizontal ? parent.width : (Settings.barPositionRight ? parent.width - radius : 0)
            y: Settings.barHorizontal ? (Settings.barPositionBottom ? parent.height - radius : 0) : parent.height
            visible: !root.flyoutFarClamped && parent.opacity > 0
        }

        // Signal skin: hairline around every side but the bar's, flowing on
        // from the fillets.
        Shape {
            anchors.fill: flyout
            z: 1
            visible: flyout.visible
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 1
                strokeColor: Colours.signalStyle.hairline
                fillColor: "transparent"

                PathSvg {
                    path: {
                        const w = flyout.width, h = flyout.height;
                        const r = Math.min(Tokens.rounding.medium, w / 2, h / 2);
                        if (Settings.barHorizontal && Settings.barPositionBottom)
                            return `M0,${h} L0,${r} A${r},${r} 0 0 1 ${r},0 L${w - r},0 A${r},${r} 0 0 1 ${w},${r} L${w},${h}`;
                        if (!Settings.barHorizontal && !Settings.barPositionRight)
                            return `M0,0 L${w - r},0 A${r},${r} 0 0 1 ${w},${r} L${w},${h - r} A${r},${r} 0 0 1 ${w - r},${h} L0,${h}`;
                        if (!Settings.barHorizontal)
                            return `M${w},0 L${r},0 A${r},${r} 0 0 0 0,${r} L0,${h - r} A${r},${r} 0 0 0 ${r},${h} L${w},${h}`;
                        return `M0,0 L0,${h - r} A${r},${r} 0 0 0 ${r},${h} L${w - r},${h} A${r},${r} 0 0 0 ${w},${h - r} L${w},0`;
                    }
                }
            }
        }

        StyledRect {
            id: flyout

            anchors.fill: parent
            visible: opacity > 0
            opacity: flyoutWrap.opacity
            // Bar-side corners are square; the ConcaveCorner wings supply
            // the fillet between the side edge and the bar.
            topLeftRadius: (Settings.barHorizontal ? !Settings.barPositionBottom : !Settings.barPositionRight) ? 0 : Tokens.rounding.medium
            topRightRadius: (Settings.barHorizontal ? !Settings.barPositionBottom : Settings.barPositionRight) ? 0 : Tokens.rounding.medium
            bottomLeftRadius: (Settings.barHorizontal ? Settings.barPositionBottom : !Settings.barPositionRight) ? 0 : Tokens.rounding.medium
            bottomRightRadius: (Settings.barHorizontal ? Settings.barPositionBottom : Settings.barPositionRight) ? 0 : Tokens.rounding.medium
            color: Colours.signalStyle.bar

            // Plain MouseArea, not HoverHandler -- see BarWrapper.qml's
            // hoverArea comment for the general reasoning. No buttons
            // accepted, so a click still reaches the popout content
            // underneath (Settings toggles, media seek bar, etc.).
            MouseArea {
                id: flyoutHover

                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                hoverEnabled: true

                onContainsMouseChanged: {
                    // Entering the flyout also REVIVES hasCurrent, not just
                    // guards against clearing it (see hoveringFlyout above):
                    // the bar's hover-exit fires the instant the pointer
                    // leaves its thin strip, which near a tall edge-clamped
                    // flyout can land the pointer in the gap between bar
                    // and flyout for a frame or two. That blip already set
                    // hasCurrent false, so entering the still-fading flyout
                    // used to do nothing -- the close timer ran out under
                    // the user's cursor and the popout disappeared while
                    // they were hovering it. Reviving here means arriving
                    // anywhere inside the flyout while it is still visible
                    // keeps the same popout open.
                    if (containsMouse) {
                        flyoutHoverExitTimer.stop();
                        root.hasCurrent = true;
                    } else {
                        // Debounced, not instant -- absorbs a same-frame
                        // flicker right at a rounded corner or while the
                        // flyout's width/height Behaviors are still resizing
                        // the geometry this handler tracks, without making a
                        // genuine leave feel laggy to close.
                        flyoutHoverExitTimer.restart();
                    }
                }
            }

            Timer {
                id: flyoutHoverExitTimer
                interval: 60
                onTriggered: {
                    // containsMouse, not hovered -- flyoutHover is a MouseArea
                    // (see above) and has no `hovered` property; that stale
                    // reference used to close this unconditionally on every
                    // fire. Functionally near-inert in practice (the entered
                    // branch above stops this while genuinely still
                    // hovering), but correct now.
                    if (!flyoutHover.containsMouse)
                        root.hasCurrent = false;
                }
            }

            Item {
                id: slideHost

                width: parent.width
                height: parent.height

                Loader {
                    id: loader

                    property bool contentRevealed: false

                    anchors.centerIn: parent
                    active: root.showContent
                    // A Timer, not a SequentialAnimation's PauseAnimation inside
                    // Behavior -- that form restarted from scratch on every
                    // rehover, so content never actually appeared unless the
                    // pointer held still through one full uninterrupted pause.
                    opacity: contentRevealed ? 1 : 0

                    Behavior on opacity {
                        Anim { type: Anim.DefaultEffects }
                    }

                    Timer {
                        id: revealTimer
                        interval: 70
                        onTriggered: loader.contentRevealed = true
                    }

                    Connections {
                        target: root
                        function onHasCurrentChanged(): void {
                            if (root.hasCurrent) {
                                revealTimer.restart();
                            } else {
                                revealTimer.stop();
                                loader.contentRevealed = false;
                            }
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
                        case "vpn":
                            return vpnComp;
                        case "battery":
                            return batteryComp;
                        case "resources":
                            return resourcesComp;
                        case "networkspeed":
                            return networkSpeedComp;
                        case "hostinfo":
                            return hostInfoComp;
                        case "pomodoro":
                            return pomodoroComp;
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
                        case "taskgroup":
                            return taskGroupComp;
                        default:
                            return null;
                        }
                    }
                }
            }
        }
    }

    Item {
        id: agentFlyoutWrap

        // Own along-axis anchor (agentCenter), not currentCenter/flyout.x --
        // binding to flyout.x/flyout.y directly with no Behavior made
        // hovering any other bar icon drag this popout instantly to that
        // icon's position, reading as "the agent popout is replacing
        // whatever I'm hovering" instead of staying put next to the agent
        // icon. Same along-axis formula flyout uses, keyed on agentCenter.
        // Zero gap against the bar, same reasoning as flyout above.
        x: root.agentFlyoutX
        y: root.agentFlyoutY
        width: root.agentNonAnimWidth
        height: root.agentNonAnimHeight

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

        transformOrigin: Settings.barHorizontal ? (Settings.barPositionBottom ? Item.Bottom : Item.Top) : (Settings.barPositionRight ? Item.Right : Item.Left)
        state: root.screenState.agentPanel ? "open" : (root.agentClosing ? "closing" : "hidden")
        states: [
            State {
                name: "open"
                PropertyChanges { target: agentFlyoutWrap; scale: 1.0; opacity: 1.0 }
            },
            State {
                name: "closing"
                PropertyChanges { target: agentFlyoutWrap; scale: 0.96; opacity: 0.0 }
            },
            State {
                name: "hidden"
                PropertyChanges { target: agentFlyoutWrap; scale: 0.94; opacity: 0.0 }
            }
        ]
        Behavior on scale {
            Anim { type: root.screenState.agentPanel ? Anim.Emphasized : Anim.EmphasizedSmall }
            enabled: root.screenState.agentPanel || root.agentClosing
        }
        Behavior on opacity {
            Anim { type: root.screenState.agentPanel ? Anim.DefaultEffects : Anim.FastEffects }
            enabled: root.screenState.agentPanel || root.agentClosing
        }

        Elevation {
            target: agentFlyout
            level: 2
            topLeftRadius: agentFlyout.topLeftRadius
            topRightRadius: agentFlyout.topRightRadius
            bottomLeftRadius: agentFlyout.bottomLeftRadius
            bottomRightRadius: agentFlyout.bottomRightRadius
        }

        ConcaveCorner {
            id: agentWingStart

            radius: Tokens.rounding.medium
            color: agentFlyout.color
            edgeColor: Colours.signalStyle.hairline
            corner: Settings.barHorizontal ? (Settings.barPositionBottom ? 2 : 0) : (Settings.barPositionRight ? 2 : 3)
            x: Settings.barHorizontal ? -radius : (Settings.barPositionRight ? parent.width - radius : 0)
            y: Settings.barHorizontal ? (Settings.barPositionBottom ? parent.height - radius : 0) : -radius
            visible: !root.agentNearClamped && parent.opacity > 0
        }
        ConcaveCorner {
            id: agentWingEnd

            radius: Tokens.rounding.medium
            color: agentFlyout.color
            edgeColor: Colours.signalStyle.hairline
            corner: Settings.barHorizontal ? (Settings.barPositionBottom ? 3 : 1) : (Settings.barPositionRight ? 0 : 1)
            x: Settings.barHorizontal ? parent.width : (Settings.barPositionRight ? parent.width - radius : 0)
            y: Settings.barHorizontal ? (Settings.barPositionBottom ? parent.height - radius : 0) : parent.height
            visible: !root.agentFarClamped && parent.opacity > 0
        }

        StyledRect {
            id: agentFlyout

            anchors.fill: parent
            visible: opacity > 0
            opacity: agentFlyoutWrap.opacity
            topLeftRadius: (Settings.barHorizontal ? !Settings.barPositionBottom : !Settings.barPositionRight) ? 0 : Tokens.rounding.medium
            topRightRadius: (Settings.barHorizontal ? !Settings.barPositionBottom : Settings.barPositionRight) ? 0 : Tokens.rounding.medium
            bottomLeftRadius: (Settings.barHorizontal ? Settings.barPositionBottom : !Settings.barPositionRight) ? 0 : Tokens.rounding.medium
            bottomRightRadius: (Settings.barHorizontal ? Settings.barPositionBottom : Settings.barPositionRight) ? 0 : Tokens.rounding.medium
            color: Colours.signalStyle.bar

            Loader {
                id: agentLoader

                anchors.centerIn: parent
                active: root.agentShowContent
                sourceComponent: AgentPopout {
                    screenState: root.screenState
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
        id: vpnComp
        VpnPopout {}
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
        id: networkSpeedComp
        NetworkSpeedPopout {}
    }
    Component {
        id: hostInfoComp
        HostInfoPopout {}
    }
    Component {
        id: pomodoroComp
        PomodoroPopout {}
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
    Component {
        id: taskGroupComp
        TaskGroupPopout {
            group: root.currentTaskGroup
        }
    }

    // A launcher, dashboard or any other surface taking the keyboard on
    // this screen settles the hover popout under it (services/Surfaces.qml).
    Connections {
        target: root.screenState

        function onEngagedChanged(): void {
            if (root.screenState.engaged)
                root.hasCurrent = false;
        }
    }
}
