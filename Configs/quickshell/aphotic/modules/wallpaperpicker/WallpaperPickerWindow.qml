pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    required property ScreenState screenState

    WlrLayershell.namespace: "aphotic-wallpaperpicker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    visible: screenState.wallpaperPicker
    implicitWidth: screen.width
    implicitHeight: screen.height

    WallpaperBackdrop {
        anchors.fill: parent
        active: root.screenState.wallpaperPicker
        source: filmstrip.backdropSource
        bandHeight: filmstrip.bandHeight
        fadeExtent: filmstrip.bandFade
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.screenState.wallpaperPicker = false
    }

    WallpaperFilmstrip {
        id: filmstrip

        anchors.fill: parent
        screenState: root.screenState
    }
}
