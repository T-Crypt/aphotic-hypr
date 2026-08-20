pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components
import qs.modules.bar.popouts as BarPopouts

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    required property ScreenState screenState
    readonly property BarPopouts.Wrapper popouts: popouts

    readonly property int barWidth: Tokens.sizes.bar.innerWidth + Config.border.thickness * 2

    WlrLayershell.namespace: "noctis-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Normal
    WlrLayershell.exclusiveZone: barWidth
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true

    // Wider than barWidth to give the popout flyout (drawn to the right of
    // the bar strip, see popouts/Wrapper.qml) real surface to paint into —
    // Wayland layer-shell surfaces clip anything outside their own bounds.
    // exclusionZone above stays pinned to barWidth so this extra space
    // doesn't reserve desktop area.
    implicitWidth: barWidth + Tokens.spacing.small * 2 + 320

    BarPopouts.Wrapper {
        id: popouts
        screen: root.screen
        barWidth: root.barWidth
    }

    BarWrapper {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        screen: root.screen
        screenState: root.screenState
        popouts: root.popouts
        fullscreen: false
    }
}
