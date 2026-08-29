// ColorPicker.qml -- single-pixel eyedropper, IPC-triggered, per-screen overlay
pragma ComponentBehavior: Bound

import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    property bool active

    function toggle(): void {
        root.active = !root.active;
    }

    Loader {
        active: root.active

        sourceComponent: Variants {
            model: Quickshell.screens

            PanelWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                visible: true

                WlrLayershell.namespace: "aphotic:colorpicker"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                color: "transparent"

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                EyedropperPicker {
                    loader: root
                    screen: win.modelData
                }
            }
        }
    }

    IpcHandler {
        target: "colorpicker"

        function toggle(): void {
            root.toggle();
        }
    }
}
