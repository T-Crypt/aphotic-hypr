pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    required property ScreenState screenState

    WlrLayershell.namespace: "aphotic-intelligence"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    implicitWidth: screen.width
    implicitHeight: screen.height

    // Geometry here is completely static (full-screen, non-exclusive,
    // never animated) -- animating a layer-shell surface's own anchors/
    // margins/size forces Wayland to renegotiate the surface and produces
    // visible geometry glitches. The actual open/close motion lives
    // entirely on IntelligenceContent's own transform (x/scale/opacity),
    // a plain QtQuick Item inside this static window. `showContent` keeps
    // the window itself mapped through the close transition (mirroring
    // modules/bar/popouts/Wrapper.qml's identical showContent/closeTimer
    // pattern) instead of yanking `visible` false mid-animation and
    // cutting it short.
    readonly property bool open: root.screenState.intelligence
    property bool showContent: root.open

    onOpenChanged: {
        if (root.open)
            root.showContent = true;
        else
            closeTimer.start();
    }

    // Matches IntelligenceContent's card animation duration
    // (Anim.Emphasized -> durations.normal) so the window stays mounted
    // through the full slide-out instead of cutting it short.
    Timer {
        id: closeTimer
        interval: Tokens.anim.durations.normal
        onTriggered: root.showContent = false
    }

    visible: root.showContent

    MouseArea {
        anchors.fill: parent
        focus: true
        onClicked: root.screenState.intelligence = false

        Keys.onEscapePressed: root.screenState.intelligence = false
    }

    IntelligenceContent {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        screenState: root.screenState
    }
}
