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

    // Declared before the content so it sits under it: children of
    // DashboardContent still take their own clicks, and this only catches
    // what falls through the gaps between them. Without it any click that
    // misses an interactive control -- card padding, the run strip's
    // overflow indicator -- reaches the dismiss handler above and closes
    // the dashboard from inside its own border.
    MouseArea {
        anchors.centerIn: parent
        width: content.width
        height: content.height
        acceptedButtons: Qt.AllButtons
    }

    DashboardContent {
        id: content

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
