pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.services

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    required property ScreenState screenState

    WlrLayershell.namespace: "aphotic-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    visible: reveal.active && !Surfaces.suppressed
    implicitWidth: screen.width
    implicitHeight: screen.height

    MouseArea {
        anchors.fill: parent
        onClicked: root.screenState.launcher = false
    }

    SurfaceReveal {
        id: reveal

        anchors.centerIn: parent
        shown: root.screenState.launcher
        edge: "bottom"
        hiddenScale: 0.96

        Launcher {
            screenState: root.screenState
            reveal: reveal
        }
    }
}
