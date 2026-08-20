pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    readonly property ScreenState screenState: ScreenState {
        modelData: root.screen
    }

    WlrLayershell.namespace: "noctis-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    visible: screenState.launcher
    implicitWidth: screen.width
    implicitHeight: screen.height

    MouseArea {
        anchors.fill: parent
        onClicked: root.screenState.launcher = false
    }

    Launcher {
        anchors.centerIn: parent
        screenState: root.screenState
    }
}
