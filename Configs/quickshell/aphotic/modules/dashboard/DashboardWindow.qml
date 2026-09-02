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

    // Gated on the state rather than this window's own `visible`: the
    // loader evaluates `active` during its own completion, before the
    // window's visible binding has settled, and would latch a watch open
    // for the whole session.
    LazyLoader {
        active: root.screenState.dashboard

        SystemUsageWatch {}
    }
}
