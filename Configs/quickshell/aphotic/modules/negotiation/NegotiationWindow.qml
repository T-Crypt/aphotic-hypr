pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services
import qs.services.profile

// Same static full-screen PanelWindow + centred animating child as every
// other modal surface in this shell (see modules/pkginstall) -- the window
// itself never moves or resizes, NegotiationContent's card does the
// motion.
//
// Instantiated by shell.qml's LazyLoader only while a negotiation is
// pending, rather than one always-mounted instance per screen: with no
// opt-in profile installed there is no negotiation, so this surface does
// not exist at all on a base install. `screen` is latched once on
// creation instead of bound to the focused monitor, so answering the
// prompt can't make the window hop screens mid-decision.
PanelWindow {
    id: root

    property var latchedScreen: null

    screen: root.latchedScreen

    WlrLayershell.namespace: "aphotic-negotiation"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    // Existence is the gate, not a second condition on ResourceEngine.pending:
    // shell.qml's loader already holds this window mounted for one animation
    // duration past the answer, and binding visible to `pending` as well
    // would unmap the surface on the first frame of that fade-out.
    visible: root.latchedScreen !== null
    implicitWidth: root.screen?.width ?? 0
    implicitHeight: root.screen?.height ?? 0

    Component.onCompleted: {
        const name = Hypr.focusedMonitor?.name;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === name) {
                root.latchedScreen = screens[i];
                return;
            }
        }
        root.latchedScreen = screens[0] ?? null;
    }

    // Escape and click-outside answer "Keep Running" -- the decision that
    // stops nothing. A dismissal must never be the one that suspends a
    // workload.
    MouseArea {
        anchors.fill: parent
        focus: true
        onClicked: ResourceEngine.resolve("keep")

        Keys.onEscapePressed: ResourceEngine.resolve("keep")
    }

    NegotiationContent {
        anchors.centerIn: parent
    }
}
