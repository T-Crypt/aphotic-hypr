// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

// Same shape as the greeter's window, and for the same reason: there is
// no desktop shell running to layer against, so a fullscreen,
// keyboard-exclusive overlay is all this needs. Exclusive focus matters
// here -- the bar and launcher are gone, and a recovery screen the user
// can type past is a recovery screen they will lose behind a window.
PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "aphotic-recovery"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: Colours.background

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    RecoveryContent {
        anchors.centerIn: parent
        width: Math.min(720, root.width - 96)
        maxHeight: root.height - 96
    }
}
