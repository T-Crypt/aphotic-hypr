pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.services

PanelWindow {
    id: root

    required property var modelData
    required property ScreenState screenState
    screen: modelData

    WlrLayershell.namespace: "aphotic-workspace"
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
    visible: screenState.workspace && PluginRegistry.surfacesFor("workspace").length > 0

    MouseArea {
        anchors.fill: parent
        focus: true
        onClicked: root.screenState.workspace = false
        Keys.onEscapePressed: root.screenState.workspace = false
    }

    MouseArea {
        anchors.centerIn: parent
        width: content.width
        height: content.height
        acceptedButtons: Qt.AllButtons
    }

    WorkspaceContent {
        id: content
        anchors.centerIn: parent
        width: Math.min(parent.width - 96, 1520)
        height: Math.min(parent.height - 128, 920)
        surfaceActive: root.visible
    }
}
