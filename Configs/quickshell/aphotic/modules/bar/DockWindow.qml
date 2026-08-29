pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    required property ScreenState screenState

    // Real, reported bug this fixes: this used to be a full-screen
    // transparent overlay (anchored to all four edges) with
    // ExclusionMode.Ignore -- floating over whatever was underneath by
    // design, like every other overlay in this repo (Notifications/OSD/
    // Dashboard/...). But those are all click-to-open transient surfaces;
    // Dock is a permanently-on bar style, and "fits within the margins
    // the way the other bar styles do, doesn't sit on top of tiled
    // windows" is a reasonable, explicitly requested expectation for
    // that -- Full/Taskbar/Minimal all reserve real desktop space via a
    // real exclusiveZone (see BarWrapper.qml). Ignore was never a
    // deliberate "Dock should float over content" design choice, it was
    // just the only option that made sense for a window anchored to all
    // four edges at once -- Wayland's exclusive-zone concept only has a
    // well-defined meaning for a window anchored to ONE edge (or a
    // full-span pair), which a corner-to-corner overlay isn't. Anchoring
    // to just the configured docked edge instead (matching
    // BarWindow.qml's own anchor pattern exactly) makes a real
    // exclusiveZone possible, while the pill itself still renders
    // centered and floating-looking within that now-edge-spanning strip
    // -- no visual change to the pill, just a real reservation behind it.
    WlrLayershell.namespace: "aphotic-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Normal
    WlrLayershell.exclusiveZone: root.reservedThickness
    color: "transparent"

    anchors.top: Settings.barHorizontal ? !Settings.barPositionBottom : true
    anchors.bottom: Settings.barHorizontal ? Settings.barPositionBottom : true
    anchors.left: Settings.barHorizontal ? true : !Settings.barPositionRight
    anchors.right: Settings.barHorizontal ? true : Settings.barPositionRight

    readonly property int edgeMargin: Tokens.padding.large
    // Dock's own auto-hide is a content-transform (translate + opacity,
    // see DockBar.qml's shouldShow), never a window resize/re-anchor --
    // matches this repo's shared popout/bar animation discipline. So the
    // reserved zone itself doesn't collapse to 0 in autohide mode; it
    // stays reserved (a thin, real strip) the same way Full/Taskbar's own
    // "autohide" bar visibility mode keeps a reserved sliver rather than
    // reclaiming the space outright (see BarWrapper.qml's exclusiveZone
    // comment) -- consistent behavior across every bar style, not a new
    // Dock-specific rule.
    readonly property int reservedThickness: (Settings.barHorizontal ? dockBar.implicitHeight : dockBar.implicitWidth) + edgeMargin

    readonly property bool dockedTop: Settings.barHorizontal && !Settings.barPositionBottom
    readonly property bool dockedBottom: Settings.barHorizontal && Settings.barPositionBottom
    readonly property bool dockedLeft: !Settings.barHorizontal && !Settings.barPositionRight
    readonly property bool dockedRight: !Settings.barHorizontal && Settings.barPositionRight

    implicitWidth: Settings.barHorizontal ? screen.width : reservedThickness
    implicitHeight: Settings.barHorizontal ? reservedThickness : screen.height

    visible: Settings.barStyle === "dock"

    mask: Region {
        item: dockBar
    }

    DockBar {
        id: dockBar

        screen: root.screen
        screenState: root.screenState

        // root's own thin-axis size is exactly dockBar's thickness +
        // edgeMargin (see reservedThickness above) -- pinning the pill
        // to the edge of root OPPOSITE the docked screen edge naturally
        // leaves exactly edgeMargin of gap on the docked side and none
        // on the other, with no manual arithmetic needed. Centered along
        // the long axis either way.
        anchors.horizontalCenter: Settings.barHorizontal ? root.horizontalCenter : undefined
        anchors.verticalCenter: Settings.barHorizontal ? undefined : root.verticalCenter
        anchors.top: root.dockedBottom ? root.top : undefined
        anchors.bottom: root.dockedTop ? root.bottom : undefined
        anchors.left: root.dockedRight ? root.left : undefined
        anchors.right: root.dockedLeft ? root.right : undefined
    }
}
