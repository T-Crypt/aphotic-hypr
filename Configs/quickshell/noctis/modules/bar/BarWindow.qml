pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services
import qs.modules.bar.popouts as BarPopouts

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    required property ScreenState screenState
    readonly property BarPopouts.Wrapper popouts: popouts

    readonly property int barWidth: Settings.barInnerWidth + Math.max(Tokens.padding.small, Config.border.thickness) * 2

    WlrLayershell.namespace: "noctis-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Normal
    WlrLayershell.exclusiveZone: barWidth
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: !Settings.barPositionRight
    anchors.right: Settings.barPositionRight

    // Wider than barWidth to give the popout flyout (drawn on the side of
    // the bar strip facing away from the docked screen edge, see
    // popouts/Wrapper.qml) real surface to paint into -- Wayland
    // layer-shell surfaces clip anything outside their own bounds.
    // exclusionZone above stays pinned to barWidth so this extra space
    // doesn't reserve desktop area. Anchoring right instead of left just
    // flips which screen edge implicitWidth grows away from -- the strip
    // itself stays flush against whichever edge is docked (see
    // BarWrapper.qml's anchor mirroring below).
    implicitWidth: barWidth + Tokens.spacing.small * 2 + 320

    BarPopouts.Wrapper {
        id: popouts
        screen: root.screen
        barWidth: root.barWidth
        windowWidth: root.width
    }

    BarWrapper {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: !Settings.barPositionRight ? parent.left : undefined
        anchors.right: Settings.barPositionRight ? parent.right : undefined
        screen: root.screen
        screenState: root.screenState
        popouts: root.popouts
        fullscreen: false
    }
}
