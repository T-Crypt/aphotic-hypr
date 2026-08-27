pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    required property ScreenState screenState

    WlrLayershell.namespace: "aphotic-notificationcenter"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    implicitWidth: screen.width
    implicitHeight: screen.height

    readonly property bool open: root.screenState.notificationCenter
    property bool showContent: root.open

    onOpenChanged: {
        if (root.open)
            root.showContent = true;
        else
            closeTimer.start();
    }

    Timer {
        id: closeTimer
        interval: Tokens.anim.durations.expressiveFastEffects
        onTriggered: root.showContent = false
    }

    visible: root.showContent

    MouseArea {
        anchors.fill: parent
        focus: true
        onClicked: root.screenState.notificationCenter = false

        Keys.onEscapePressed: root.screenState.notificationCenter = false
    }

    NotificationCenterContent {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        screenState: root.screenState
    }
}
