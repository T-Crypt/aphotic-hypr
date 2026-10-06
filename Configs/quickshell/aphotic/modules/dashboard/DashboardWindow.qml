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

    WlrLayershell.namespace: "aphotic-dashboard"
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

    // Signal: dim and (through the compositor's layer rule) frost the
    // desktop behind the dashboard.
    Rectangle {
        anchors.fill: parent
        color: Colours.palette.m3shadow
        opacity: reveal.visibleProgress * 0.35
    }

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

        // The wheel steps through tabs wherever the content under the
        // pointer does not scroll itself. One step per notch.
        property real wheelAccum: 0
        onWheel: wheel => {
            wheelAccum += wheel.angleDelta.y;
            while (Math.abs(wheelAccum) >= 120) {
                content.stepTab(wheelAccum > 0 ? -1 : 1);
                wheelAccum -= wheelAccum > 0 ? 120 : -120;
            }
        }
    }

    SurfaceReveal {
        id: reveal

        anchors.centerIn: parent
        shown: root.screenState.dashboard

        DashboardContent {
            id: content

            screenState: root.screenState
        }
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
