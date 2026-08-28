// BackgroundWindow.qml -- per-screen wallpaper + optional desktop clock overlay
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.config
import qs.services

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    required property ScreenState screenState

    readonly property string currentWallpaper: Wallpapers.current

    visible: Config.background.enabled && Config.background.wallpaperEnabled

    WlrLayershell.namespace: "aphotic-background"
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

        // Desktop right-click menu -- TapHandler (not MouseArea) so it
        // observes without grabbing the button, leaving normal
        // left-click-through-to-desktop behaviour untouched.
        property bool menuOpen: false
        property real menuX: 0
        property real menuY: 0

        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: eventPoint => {
                backgroundContent.menuX = eventPoint.position.x;
                backgroundContent.menuY = eventPoint.position.y;
                backgroundContent.menuOpen = true;
            }
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            enabled: backgroundContent.menuOpen
            onTapped: backgroundContent.menuOpen = false
        }

        Loader {
            id: contextMenuLoader

            // Above the wallpaper/clock siblings below regardless of
            // declaration order (QML stacks same-parent children by
            // declaration order otherwise, and this is declared first).
            z: 100
            active: backgroundContent.menuOpen
            asynchronous: false

            sourceComponent: DesktopContextMenu {
                screenState: root.screenState
                menuX: backgroundContent.menuX
                menuY: backgroundContent.menuY
                onDismissed: backgroundContent.menuOpen = false
            }
        }

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
            active: Settings.desktopClockEnabled

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
                    easing: Tokens.anim.expressiveDefaultSpatial
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
