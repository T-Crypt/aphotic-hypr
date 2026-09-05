pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

// The whole point of this being a *separate* qs config from the live
// desktop shell: this runs inside a throwaway Hyprland instance greetd
// spins up just to host this one client (see
// Configs/greetd/hyprland-greeter.conf) -- there is no real desktop
// session, no D-Bus, no other windows to layer against. A plain
// fullscreen, keyboard-exclusive overlay layer is all this needs.
PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "aphotic-greeter"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Wallpaper {
        anchors.fill: parent
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Colours.background, 0.55)
    }

    GreeterContent {
        anchors.centerIn: parent
        auth: auth
    }

    GreeterAuth {
        id: auth
    }
}
