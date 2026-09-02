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

    WlrLayershell.namespace: "aphotic-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    visible: screenState.settings
    implicitWidth: screen.width
    implicitHeight: screen.height

    // Jump-to-category handoff from the launcher's "?" settings-search
    // mode (Launcher.qml/SettingsItem.qml) -- same one-shot
    // set-then-clear shape as Launcher.qml's own launcherPrefill
    // consumption.
    onVisibleChanged: {
        if (visible && screenState.settingsCategory !== "") {
            settingsPanel.currentCategory = screenState.settingsCategory;
            screenState.settingsCategory = "";
        }
    }

    MouseArea {
        anchors.fill: parent
        focus: true
        onClicked: root.screenState.settings = false

        Keys.onEscapePressed: root.screenState.settings = false
    }

    SettingsPanel {
        id: settingsPanel

        anchors.centerIn: parent
        screenState: root.screenState
    }

    // Gated on the state rather than this window's own `visible`: the
    // loader evaluates `active` during its own completion, before the
    // window's visible binding has settled, and would latch a watch open
    // for the whole session.
    LazyLoader {
        active: root.screenState.settings

        SystemUsageWatch {}
    }
}
