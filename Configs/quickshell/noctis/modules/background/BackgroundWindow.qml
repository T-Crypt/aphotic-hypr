// BackgroundWindow.qml -- per-screen wallpaper + optional desktop clock overlay
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

    readonly property string currentWallpaper: Wallpapers.current

    visible: Config.background.enabled && Config.background.wallpaperEnabled

    WlrLayershell.namespace: "noctis-background"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "black"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Item {
        id: backgroundContent

        anchors.fill: parent

        Loader {
            id: wallpaperDisplay

            anchors.fill: parent
            asynchronous: true
            active: Config.background.wallpaperEnabled

            sourceComponent: Wallpaper {
                source: root.currentWallpaper
            }
        }

        Loader {
            id: clockLoader

            asynchronous: true
            active: Config.background.desktopClock.enabled

            anchors.margins: Tokens.padding.large * 2
            anchors.leftMargin: Tokens.padding.large * 2 + Tokens.sizes.bar.innerWidth + Config.border.thickness

            state: Config.background.desktopClock.position

            states: [
                State {
                    name: "top-left"
                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "top-center"
                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "top-right"
                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "middle-left"
                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "middle-center"
                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "middle-right"
                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "bottom-left"
                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "bottom-center"
                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "bottom-right"
                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                    }
                }
            ]

            transitions: Transition {
                AnchorAnimation {
                    duration: Tokens.anim.durations.expressiveDefaultSpatial
                }
            }

            sourceComponent: DesktopClock {
                wallpaper: backgroundContent
                absX: clockLoader.x
                absY: clockLoader.y
            }
        }
    }
}
