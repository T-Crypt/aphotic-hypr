// AreaPicker.qml -- region screenshot picker, IPC-triggered, per-screen overlay
pragma ComponentBehavior: Bound

import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    property bool active
    property bool closing
    property bool freeze
    property bool clipboardOnly

    Loader {
        active: root.active

        sourceComponent: Variants {
            model: Quickshell.screens

            PanelWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                visible: true

                WlrLayershell.namespace: "noctis:areapicker"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: root.closing ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                color: "transparent"

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                Picker {
                    loader: root
                    screen: win.modelData
                }
            }
        }
    }

    IpcHandler {
        target: "picker"

        function open(): void {
            root.freeze = false;
            root.clipboardOnly = false;
            root.closing = false;
            root.active = true;
        }

        function openFreeze(): void {
            root.freeze = true;
            root.clipboardOnly = false;
            root.closing = false;
            root.active = true;
        }

        function openClip(): void {
            root.freeze = false;
            root.clipboardOnly = true;
            root.closing = false;
            root.active = true;
        }

        function openFreezeClip(): void {
            root.freeze = true;
            root.clipboardOnly = true;
            root.closing = false;
            root.active = true;
        }
    }

    CustomShortcut {
        name: "pickerOpen"
        description: "Open the area picker"
        onPressed: {
            root.freeze = false;
            root.clipboardOnly = false;
            root.closing = false;
            root.active = true;
        }
    }

    CustomShortcut {
        name: "pickerOpenFreeze"
        description: "Open the area picker in freeze mode"
        onPressed: {
            root.freeze = true;
            root.clipboardOnly = false;
            root.closing = false;
            root.active = true;
        }
    }

    CustomShortcut {
        name: "pickerOpenClip"
        description: "Open the area picker, clipboard only"
        onPressed: {
            root.freeze = false;
            root.clipboardOnly = true;
            root.closing = false;
            root.active = true;
        }
    }

    CustomShortcut {
        name: "pickerOpenFreezeClip"
        description: "Open the area picker in freeze mode, clipboard only"
        onPressed: {
            root.freeze = true;
            root.clipboardOnly = true;
            root.closing = false;
            root.active = true;
        }
    }
}
