pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
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
        visible: !Settings.barSignal
    }

    // Signal: the wallpaper, blurred once into a static texture, under the
    // same darkening gradient the login greeter uses.
    Image {
        id: wallpaper

        anchors.fill: parent
        visible: false
        source: Settings.barSignal ? Wallpapers.current : ""
        sourceSize.width: 1920
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        onStatusChanged: if (status === Image.Ready) wallpaperTexture.scheduleUpdate()
    }

    ShaderEffectSource {
        id: wallpaperTexture

        anchors.fill: parent
        visible: false
        sourceItem: wallpaper
        live: false
    }

    MultiEffect {
        anchors.fill: parent
        visible: Settings.barSignal && wallpaper.status === Image.Ready
        source: wallpaperTexture
        blurEnabled: true
        blur: 0.55
        blurMax: 48
        saturation: -0.1
    }

    Rectangle {
        anchors.fill: parent
        visible: Settings.barSignal
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.35)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.8)
            }
        }
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
