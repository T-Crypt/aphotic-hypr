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

    property bool everOpened: false

    WlrLayershell.namespace: "aphotic-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    visible: root.screenState.launcher || root.everOpened
    implicitWidth: screen.width
    implicitHeight: screen.height

    MouseArea {
        anchors.fill: parent
        onClicked: root.screenState.launcher = false
    }

    // Matches Launcher's fade so the panel is released after it ends.
    Timer {
        id: releasePanel
        interval: Tokens.anim.durations.expressiveDefaultSpatial
        onTriggered: root.everOpened = false
    }

    Loader {
        id: launcherLoader

        anchors.centerIn: parent
        focus: true
        active: root.screenState.launcher || root.everOpened
        sourceComponent: launcherComp
    }

    Component {
        id: launcherComp

        Launcher {
            screenState: root.screenState
        }
    }

    Connections {
        target: root.screenState

        function onLauncherChanged(): void {
            if (root.screenState.launcher) {
                releasePanel.stop();
                root.everOpened = true;
            } else {
                releasePanel.restart();
            }
        }
    }
}
