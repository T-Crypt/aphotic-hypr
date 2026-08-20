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

    readonly property ScreenState screenState: ScreenState {
        modelData: root.screen
        bar: true
    }
    readonly property BarPopouts.Wrapper popouts: popouts

    WlrLayershell.namespace: "noctis-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Auto
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true

    implicitWidth: Tokens.sizes.bar.innerWidth + Config.border.thickness * 2

    BarPopouts.Wrapper {
        id: popouts
        screen: root.screen
    }

    BarWrapper {
        anchors.fill: parent
        screen: root.screen
        screenState: root.screenState
        popouts: root.popouts
        fullscreen: false
    }
}
