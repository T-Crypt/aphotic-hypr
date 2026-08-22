pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    required property ScreenState screenState

    WlrLayershell.namespace: "aphotic-dashboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    visible: screenState.dashboard
    implicitWidth: screen.width
    implicitHeight: screen.height

    MouseArea {
        anchors.fill: parent
        focus: true
        onClicked: root.screenState.dashboard = false

        Keys.onEscapePressed: root.screenState.dashboard = false
    }

    DashboardContent {
        anchors.centerIn: parent
        screenState: root.screenState
    }
}
