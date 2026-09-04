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
    //
    // Watched on both edges. SettingsItem sets the category and only then
    // opens Settings, so a hit with the panel closed arrives as the
    // visibility change; a second hit with the panel already open never
    // changes `visible` at all and used to be dropped silently. Clearing
    // the category re-enters the handler, which the empty check ends.
    function consumeRequestedCategory(): void {
        if (!root.visible || root.screenState.settingsCategory === "")
            return;
        settingsPanel.currentCategory = root.screenState.settingsCategory;
        root.screenState.settingsCategory = "";
    }

    onVisibleChanged: root.consumeRequestedCategory()

    Connections {
        target: root.screenState

        function onSettingsCategoryChanged(): void {
            root.consumeRequestedCategory();
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
