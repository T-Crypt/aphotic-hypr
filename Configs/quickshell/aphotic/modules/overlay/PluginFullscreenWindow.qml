// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Host for one plugin-registered `fullscreen-overlay` surface on one
// screen (manifest v3.5's [ui.fullscreen-overlay]). The fifth hosted
// surface kind, and a different contract from `overlay` in every way that
// matters: that one is a fixed-budget, click-through box anchored to an
// edge, this one covers the output and takes every event on it.
//
// Anchored to all four edges rather than given a size, so the geometry is
// still static in the sense §3 rule 1 means -- the window is the output,
// it is never resized, and the plugin animates content inside it.
//
// Overlay layer, above every shell surface. An ambient overlay must never
// cover the bar; this one must cover everything, and the session lock
// still draws above it because a lock is not a layer surface at all.
//
// Exclusive keyboard focus is the point of the kind. The surface exists
// to be dismissed, so it has to be the thing receiving the keystroke that
// dismisses it rather than passing it to whatever had focus before.
PanelWindow {
    id: root

    required property var modelData
    required property var surface

    // Real input is anything the compositor did not already deliver while
    // the surface was still mapping. Without this a pointer that happened
    // to be moving as the window appeared dismisses it in the same frame
    // it arrived, which reads as the screensaver never starting.
    property bool armed: false

    function dismiss(): void {
        if (root.armed)
            FullscreenOverlays.dismiss(root.surface);
    }

    screen: modelData

    WlrLayershell.namespace: `aphotic-fullscreen-${root.surface.id}`
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.exclusiveZone: 0
    color: "black"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Timer {
        interval: 400
        running: true
        onTriggered: root.armed = true
    }

    Item {
        id: catcher

        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            event.accepted = true;
            root.dismiss();
        }

        Loader {
            anchors.fill: parent
            asynchronous: true
            source: root.surface.componentUrl
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            cursorShape: Qt.BlankCursor
            onPressed: root.dismiss()
            onPositionChanged: root.dismiss()
        }

        WheelHandler {
            onWheel: root.dismiss()
        }
    }
}
