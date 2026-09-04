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

    readonly property int edgeMargin: Config.bar.capsule.edgeMargin
    readonly property int collapsedThickness: Settings.barInnerWidth + Tokens.padding.extraSmall * 2
    // The zone reserves the COLLAPSED band only. Expansion is transient
    // and must never renegotiate the layer surface, so the window is
    // sized once to the largest state the capsule can reach and only the
    // inner surface moves -- the same budgeting NotchWindow.qml does.
    readonly property int reservedThickness: collapsedThickness + edgeMargin
    // Room for the pill PLUS the media popout that opens away from the
    // docked edge, so the compositor never has to renegotiate the surface
    // when it opens.
    readonly property int maxThickness: collapsedThickness + Config.bar.capsule.gap + (Settings.barHorizontal ? Config.bar.capsule.popoutHeight : Config.bar.capsule.stackedPopoutWidth)

    readonly property bool dockedTop: Settings.barHorizontal && !Settings.barPositionBottom
    readonly property bool dockedLeft: !Settings.barHorizontal && !Settings.barPositionRight

    WlrLayershell.namespace: "aphotic-capsule"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Normal
    // Same startup-race guard BarWrapper.qml/DockWindow.qml document: the
    // orientation and thickness this is derived from all load
    // asynchronously, and a reservation committed on the wrong edge does
    // not reliably shrink back afterward.
    WlrLayershell.exclusiveZone: Settings._loaded ? root.reservedThickness : 0
    color: "transparent"

    anchors.top: Settings.barHorizontal ? !Settings.barPositionBottom : true
    anchors.bottom: Settings.barHorizontal ? Settings.barPositionBottom : true
    anchors.left: Settings.barHorizontal ? true : !Settings.barPositionRight
    anchors.right: Settings.barHorizontal ? true : Settings.barPositionRight

    // Whichever axis carries both opposing anchors is anchor-driven and
    // ignores its implicit size; only the thickness axis honours this.
    implicitWidth: Settings.barHorizontal ? screen.width : root.maxThickness + root.edgeMargin * 2 + Tokens.spacing.medium
    implicitHeight: Settings.barHorizontal ? root.maxThickness + root.edgeMargin * 2 + Tokens.spacing.medium : screen.height

    visible: Settings.barStyle === "capsule"

    // Without a mask the transparent remainder of this surface swallows
    // clicks meant for whatever sits underneath, exactly as BarWindow.qml
    // documents. capsuleBar's own bounds never drop below the collapsed
    // footprint, so auto-hide keeps a real hover target.
    mask: Region {
        item: capsuleBar
    }

    CapsuleBar {
        id: capsuleBar

        screen: root.screen
        screenState: root.screenState

        // Plain x/y, not anchors -- BarWrapper.qml and DockWindow.qml both
        // document why an orientation-dependent `cond ? parent.X :
        // undefined` anchor does not reliably clear itself when the
        // persisted orientation loads and flips the condition.
        x: Settings.barHorizontal ? (parent.width - width) / 2 : (root.dockedLeft ? root.edgeMargin : parent.width - width - root.edgeMargin)
        y: Settings.barHorizontal ? (root.dockedTop ? root.edgeMargin : parent.height - height - root.edgeMargin) : (parent.height - height) / 2
    }

    WheelHandler {
        target: capsuleBar
        onWheel: event => capsuleBar.handleWheel(Settings.barHorizontal ? point.position.x : point.position.y, Qt.point(event.angleDelta.x, event.angleDelta.y))
    }
}
