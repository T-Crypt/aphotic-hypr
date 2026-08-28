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

    required property ScreenState screenState

    // Full-screen transparent overlay + region mask, same pattern every
    // other overlay window in this repo uses (Notifications/OSD/
    // Dashboard/...), rather than a native layer-shell partial-edge-
    // anchor trick -- keeps Dock's floating, non-edge-spanning geometry
    // consistent with the rest of the codebase instead of introducing a
    // second window-positioning convention.
    WlrLayershell.namespace: "aphotic-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    implicitWidth: screen.width
    implicitHeight: screen.height

    visible: Settings.barStyle === "dock"

    readonly property int edgeMargin: Tokens.padding.large

    mask: Region {
        item: dockBar
    }

    DockBar {
        id: dockBar

        screen: root.screen
        screenState: root.screenState

        x: Settings.barHorizontal ? (root.width - width) / 2 : (Settings.barPositionRight ? root.width - width - root.edgeMargin : root.edgeMargin)
        y: Settings.barHorizontal ? (Settings.barPositionBottom ? root.height - height - root.edgeMargin : root.edgeMargin) : (root.height - height) / 2
    }
}
