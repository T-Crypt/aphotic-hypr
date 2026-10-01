pragma ComponentBehavior: Bound

import qs.services
import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: win

    required property ShellScreen modelData
    readonly property bool focused: Sonar.focusOutput === modelData.name

    screen: modelData
    visible: Sonar.active && !Surfaces.suppressed
    color: "transparent"

    WlrLayershell.namespace: "aphotic:sonar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: win.focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    SonarOverlay {
        anchors.fill: parent
        screen: win.modelData
        focused: win.focused
    }

    // Delivers compositor-bound shortcuts to the focused
    // overlay so any-key dismissal covers them too. The
    // compositor may refuse the request; keys bound to the
    // shell surface still dismiss it, and the live behavior
    // is an explicit operator validation item.
    ShortcutInhibitor {
        window: win
        enabled: win.focused && Sonar.active
    }
}
