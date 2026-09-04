// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Host for one plugin-registered `overlay` surface on one screen
// (manifest v3.4's [ui.overlay]). The fourth hosted surface kind, and the
// first that is not docked inside another surface: a dashboard tab, notch
// tile and settings pane all draw inside a window core already owns,
// where an overlay is a window of its own.
//
// Core owns the window, the plugin owns only what is drawn in it. That
// split is what keeps the static-geometry rule enforceable across code
// nobody here reviews: the surface is budgeted once from the manifest's
// declared width/height and never resizes, so a plugin cannot renegotiate
// a layer surface no matter what it animates inside its own item.
//
// Region-masked so the surface does not swallow clicks meant for the
// desktop underneath -- an always-present overlay that did would be worse
// than no overlay. Same reasoning NotchWindow and BarWindow document.
//
// A plugin that paints less than its whole budget should expose a
// `maskItem` naming the part that takes input, because the loaded item
// fills the window and masking to it makes the entire declared box a dead
// zone. A pet 86px wide in a 240px surface would otherwise cost the
// desktop the other 154.
PanelWindow {
    id: root

    required property var modelData
    required property var surface

    screen: modelData

    WlrLayershell.namespace: `aphotic-overlay-${root.surface.id}`
    // Bottom, not Top: an overlay is ambient. It sits above the wallpaper
    // and below every real shell surface, so a pet or a visualiser can
    // never cover the bar, the notch or a popout.
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Normal
    WlrLayershell.exclusiveZone: 0
    color: "transparent"

    anchors.top: root.surface.anchor === "top"
    anchors.bottom: root.surface.anchor === "bottom" || root.surface.anchor === ""
    anchors.left: root.surface.anchor === "left"
    anchors.right: root.surface.anchor === "right"

    implicitWidth: root.surface.width
    implicitHeight: root.surface.height

    mask: Region {
        item: content.item?.maskItem ?? content.item ?? null
    }

    Loader {
        id: content

        anchors.fill: parent
        asynchronous: true
        source: root.surface.componentUrl
    }
}
