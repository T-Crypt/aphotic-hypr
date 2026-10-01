pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components
import qs.config
PanelWindow {
    id: root
    required property var modelData
    readonly property bool leftLoaded: leftContent.item !== null
    readonly property bool rightLoaded: rightContent.item !== null
    property bool revealing: leftReveal.active || rightReveal.active
    screen: modelData
    visible: root.revealing && !Surfaces.suppressed && !SessionLockState.locked
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "aphotic:shelves"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    MouseArea {
        objectName: "shelf-click-away"
        anchors.fill: parent
        focus: true
        onClicked: Shelves.close(root.modelData.name)
        Keys.onEscapePressed: Shelves.close(root.modelData.name)
    }
    SurfaceReveal {
        id: leftReveal
        anchors.left: parent.left
        anchors.leftMargin: Tokens.padding.small
        anchors.verticalCenter: parent.verticalCenter
        width: Settings.barInnerWidth + Tokens.padding.medium * 2
        height: Math.max(1,Math.min(640,root.height - Tokens.padding.large * 2))
        edge: "left"
        shown: Shelves.isOpen(root.modelData.name,"left")
        Loader {
            id: leftContent
            anchors.fill: parent
            active: leftReveal.active
            sourceComponent: ShelfContent { output: root.modelData.name; edge: "left" }
        }
    }
    SurfaceReveal {
        id: rightReveal
        anchors.right: parent.right
        anchors.rightMargin: Tokens.padding.small
        anchors.verticalCenter: parent.verticalCenter
        width: Settings.barInnerWidth + Tokens.padding.medium * 2
        height: Math.max(1,Math.min(640,root.height - Tokens.padding.large * 2))
        edge: "right"
        shown: Shelves.isOpen(root.modelData.name,"right")
        Loader {
            id: rightContent
            anchors.fill: parent
            active: rightReveal.active
            sourceComponent: ShelfContent { output: root.modelData.name; edge: "right" }
        }
    }
}
