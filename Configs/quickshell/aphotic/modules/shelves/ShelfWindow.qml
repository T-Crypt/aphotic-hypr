pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components
import qs.config
import qs.modules.shelves
PanelWindow {
    id: root
    required property var modelData
    readonly property bool leftLoaded: leftContent.item !== null
    readonly property bool rightLoaded: rightContent.item !== null
    property bool revealing: leftReveal.active || rightReveal.active
    // A handle is the one thing here that outlives a reveal: an edge the
    // user gave a visible handle to keeps its affordance mounted, and the
    // window stays mapped for it. Nothing else mounts while closed.
    readonly property bool handleShown: leftHandle.visible || rightHandle.visible
    readonly property bool showing: root.revealing || root.handleShown
    screen: modelData
    visible: root.showing && !Surfaces.suppressed && !SessionLockState.locked
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "aphotic:shelves"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.revealing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    // Click-away consumes the click so a shelf dismissal never lands on an
    // application behind it. It only exists while something is being
    // dismissed: a mounted handle window must not swallow desktop clicks.
    mask: Region {
        width: root.revealing ? root.width : 0
        height: root.revealing ? root.height : 0
        Region { x: leftHandle.x; y: leftHandle.y; width: leftHandle.visible ? leftHandle.width : 0; height: leftHandle.visible ? leftHandle.height : 0 }
        Region { x: rightHandle.x; y: rightHandle.y; width: rightHandle.visible ? rightHandle.width : 0; height: rightHandle.visible ? rightHandle.height : 0 }
    }
    MouseArea {
        objectName: "shelf-click-away"
        anchors.fill: parent
        enabled: root.revealing
        focus: root.revealing
        onClicked: Shelves.close(root.modelData.name)
        Keys.onEscapePressed: Shelves.close(root.modelData.name)
    }

    // Visible handles. Opt-in per edge, sized to their own bounds, clear of
    // the bar and notch, and taking no desktop space: a handle is a grab
    // target, not a strip along the edge.
    Item {
        id: leftHandle

        objectName: "shelf-handle-left"
        anchors.left: parent.left
        anchors.leftMargin: Tokens.spacing.extraSmall
        anchors.verticalCenter: parent.verticalCenter
        width: Tokens.spacing.small
        height: 72
        visible: Shelves.config(root.modelData.name).left.enabled
            && Shelves.config(root.modelData.name).left.handles
            && !Shelves.isOpen(root.modelData.name,"left")

        ShelfHandle {
            anchors.fill: parent
            edge: "left"
            onClicked: Shelves.toggle(root.modelData.name,"left")
        }
    }

    Item {
        id: rightHandle

        objectName: "shelf-handle-right"
        anchors.right: parent.right
        anchors.rightMargin: Tokens.spacing.extraSmall
        anchors.verticalCenter: parent.verticalCenter
        width: Tokens.spacing.small
        height: 72
        visible: Shelves.config(root.modelData.name).right.enabled
            && Shelves.config(root.modelData.name).right.handles
            && !Shelves.isOpen(root.modelData.name,"right")

        ShelfHandle {
            anchors.fill: parent
            edge: "right"
            onClicked: Shelves.toggle(root.modelData.name,"right")
        }
    }

    SurfaceReveal {
        id: leftReveal
        anchors.left: parent.left
        anchors.leftMargin: Tokens.padding.small + (!Settings.barHorizontal && !Settings.barPositionRight ? Settings.barInnerWidth + Tokens.padding.medium * 2 : 0)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(root.width - Tokens.padding.large * 2, Shelves.tabFor(root.modelData.name,"left") !== null ? 360 : Settings.barInnerWidth + Tokens.padding.medium * 2)
        height: Math.max(1,Math.min(640,root.height - Tokens.padding.large * 2))
        edge: "left"
        shown: Shelves.isOpen(root.modelData.name,"left")
        Loader {
            id: leftContent
            anchors.fill: parent
            active: leftReveal.active
            sourceComponent: ShelfContent { output: root.modelData.name; edge: "left"; screen: root.modelData.name }
        }
    }
    SurfaceReveal {
        id: rightReveal
        anchors.right: parent.right
        anchors.rightMargin: Tokens.padding.small + (!Settings.barHorizontal && Settings.barPositionRight ? Settings.barInnerWidth + Tokens.padding.medium * 2 : 0)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(root.width - Tokens.padding.large * 2, Shelves.tabFor(root.modelData.name,"right") !== null ? 360 : Settings.barInnerWidth + Tokens.padding.medium * 2)
        height: Math.max(1,Math.min(640,root.height - Tokens.padding.large * 2))
        edge: "right"
        shown: Shelves.isOpen(root.modelData.name,"right")
        Loader {
            id: rightContent
            anchors.fill: parent
            active: rightReveal.active
            sourceComponent: ShelfContent { output: root.modelData.name; edge: "right"; screen: root.modelData.name }
        }
    }
}