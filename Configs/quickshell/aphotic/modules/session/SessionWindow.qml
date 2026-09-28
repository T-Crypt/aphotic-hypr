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

    WlrLayershell.namespace: "aphotic-session"
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
        onClicked: root.screenState.session = false
    }

    Rectangle {
        anchors.fill: parent
        color: Colours.palette.m3shadow
        opacity: reveal.visibleProgress * 0.45
    }

    SurfaceReveal {
        id: reveal

        anchors.centerIn: parent
        shown: root.screenState.session
        hiddenScale: 0.92

        SessionContent {
            screenState: root.screenState
            reveal: reveal

            Keys.onEscapePressed: root.screenState.session = false
        }
    }
}
