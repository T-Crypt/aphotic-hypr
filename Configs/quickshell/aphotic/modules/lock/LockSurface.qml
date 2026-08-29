pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services

WlSessionLockSurface {
    id: root

    required property WlSessionLock lock
    required property var pam

    color: Colours.palette.m3surfaceContainer

    DepthLayer {
        anchors.fill: parent
    }

    LockContent {
        anchors.centerIn: parent
        lock: root.lock
        pam: root.pam
    }

    // Auth-success ripple: a soft accent-coloured glow expanding from the
    // unlock point outward, so the transition to desktop reads as a
    // deliberate "surfacing" rather than an instant cut.
    Rectangle {
        id: unlockRipple

        anchors.centerIn: parent
        width: 0
        height: width
        radius: width / 2
        color: Qt.alpha(Colours.palette.m3primary, 0.35)
        opacity: 0
        visible: width > 0

        SequentialAnimation {
            id: rippleAnim

            ScriptAction {
                script: unlockRipple.opacity = 0.55
            }
            ParallelAnimation {
                NumberAnimation {
                    target: unlockRipple
                    property: "width"
                    from: 0
                    to: Math.max(root.width, root.height) * 1.5
                    duration: Tokens.anim.durations.large
                    easing: Tokens.anim.expressiveDefaultSpatial
                }
                NumberAnimation {
                    target: unlockRipple
                    property: "opacity"
                    to: 0
                    duration: Tokens.anim.durations.large
                    easing: Tokens.anim.standardDecel
                }
            }
            ScriptAction {
                script: unlockRipple.width = 0
            }
        }

        Connections {
            target: root.pam

            function onUnlockSuccess(): void {
                rippleAnim.restart();
            }
        }
    }
}
