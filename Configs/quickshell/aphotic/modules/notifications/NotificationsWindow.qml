pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "aphotic-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.right: true

    implicitWidth: Tokens.sizes.notifs.width + Tokens.padding.large * 2
    implicitHeight: screen.height

    visible: Notifs.popups.length > 0

    ListView {
        id: list

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        width: Tokens.sizes.notifs.width
        height: Math.min(parent.height - Tokens.padding.large * 2, contentHeight)

        spacing: Tokens.spacing.medium
        clip: true

        model: ScriptModel {
            values: Notifs.popups.slice()
        }

        delegate: Notification {
            width: list.width
        }

        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1 }
        }
        remove: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0 }
        }
        move: Transition {
            NumberAnimation { property: "y" }
        }
        displaced: Transition {
            NumberAnimation { property: "y" }
        }
    }
}
