pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components
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

    // Stays mapped while the last card plays out its remove transition
    // instead of unmounting the frame mid-fade.
    readonly property int popupCount: Notifs.popups.length

    visible: root.popupCount > 0 || lingerTimer.running

    onPopupCountChanged: {
        if (root.popupCount === 0)
            lingerTimer.start();
    }

    Timer {
        id: lingerTimer
        interval: Tokens.anim.durations.expressiveDefaultEffects
    }

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
            Anim { type: Anim.DefaultEffects; property: "opacity"; from: 0; to: 1 }
        }
        remove: Transition {
            Anim { type: Anim.DefaultEffects; property: "opacity"; from: 1; to: 0 }
        }
        move: Transition {
            Anim { type: Anim.Emphasized; property: "y" }
        }
        displaced: Transition {
            Anim { type: Anim.Emphasized; property: "y" }
        }
    }
}
