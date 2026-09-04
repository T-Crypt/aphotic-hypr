pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    readonly property Notch notch: notch

    readonly property bool dockHorizontal: Settings.barHorizontal
    // Which way the hub opens: away from the edge the bar is docked
    // against, so the two never grow into each other.
    readonly property bool growsPositive: root.dockHorizontal ? !Settings.barPositionBottom : !Settings.barPositionRight

    WlrLayershell.namespace: "aphotic-notch"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Normal with a zero zone, NOT ExclusionMode.Ignore: zero reserves no
    // desktop space of its own while still honouring everyone else's
    // exclusive zone, so the bar's own reservation pushes the notch clear
    // of it instead of the notch landing on top. Ignore would set -1,
    // which means "ignore every other surface's zone".
    WlrLayershell.exclusionMode: ExclusionMode.Normal
    WlrLayershell.exclusiveZone: 0
    color: "transparent"

    // Exactly one edge, the one the bar is docked to. With a single axis
    // anchored, layer-shell centres the surface on the other -- no width
    // binding is involved in the centring, which is what keeps the surface
    // geometry static below.
    anchors.top: root.dockHorizontal && !Settings.barPositionBottom
    anchors.bottom: root.dockHorizontal && Settings.barPositionBottom
    anchors.left: !root.dockHorizontal && !Settings.barPositionRight
    anchors.right: !root.dockHorizontal && Settings.barPositionRight

    // The anchored edge is read off persisted settings that load
    // asynchronously, so the surface would otherwise commit against the
    // top edge for a frame and then jump -- the same startup race
    // BarWrapper.qml and CapsuleWindow.qml guard.
    visible: Config.notch.enabled && Settings._loaded

    // Content-INDEPENDENT surface size, sized once to the largest state
    // the notch can reach plus margin. The open panel is the same
    // rectangle in all four orientations, so one budget covers every edge
    // and an orientation flip never renegotiates anything. Every
    // expand/contract happens inside `notch`; this window never resizes,
    // so the compositor is never asked to renegotiate the layer surface on
    // a state change. Same budgeting CapsuleWindow does.
    implicitWidth: Config.notch.expandedWidth + Config.notch.surfaceMargin * 2
    implicitHeight: Config.notch.maxHeight + Config.notch.surfaceMargin * 2

    // Without this the whole (mostly transparent) surface swallows clicks
    // meant for whatever is underneath it, exactly as BarWindow documents.
    // Region tracks `notch`'s animating bounds via set_input_region, a
    // plain surface commit -- it does not resize the layer surface.
    mask: Region {
        item: notch
    }

    Notch {
        id: notch

        dockHorizontal: root.dockHorizontal
        growsPositive: root.growsPositive

        // Plain x/y rather than anchors: BarWrapper.qml and DockWindow.qml
        // both document why an orientation-dependent `cond ? parent.X :
        // undefined` anchor does not reliably clear itself when the
        // persisted orientation loads and flips the condition. Pinning the
        // docked-edge side and centring the other is also what makes the
        // panel grow away from the bar rather than about its own centre.
        x: root.dockHorizontal ? (parent.width - width) / 2 : (root.growsPositive ? Config.notch.edgeGap : parent.width - width - Config.notch.edgeGap)
        y: root.dockHorizontal ? (root.growsPositive ? Config.notch.edgeGap : parent.height - height - Config.notch.edgeGap) : (parent.height - height) / 2
    }
}
