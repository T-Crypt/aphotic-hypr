pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    readonly property Notch notch: notch

    WlrLayershell.namespace: "aphotic-notch"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Normal with a zero zone, NOT ExclusionMode.Ignore: zero reserves no
    // desktop space of its own while still honouring everyone else's
    // exclusive zone, so a top-docked bar pushes the notch below itself
    // instead of being overlapped by it. Ignore would set -1, which means
    // "ignore every other surface's zone" and lands the notch on top of
    // the bar.
    WlrLayershell.exclusionMode: ExclusionMode.Normal
    WlrLayershell.exclusiveZone: 0
    color: "transparent"

    // Top edge only. With one axis anchored, layer-shell centres the
    // surface on the other -- no width binding is involved in the
    // centring, which is what keeps the surface geometry static below.
    anchors.top: true

    visible: Config.notch.enabled

    // Content-INDEPENDENT surface size, sized once to the largest state
    // the notch can reach plus shadow bleed. Every expand/contract
    // happens inside `notch`; this window never resizes, so the
    // compositor is never asked to renegotiate the layer surface on a
    // state change. Same budgeting BarWindow does for its popout flyouts.
    implicitWidth: Config.notch.expandedWidth + Tokens.spacing.extraLarge * 2
    implicitHeight: Config.notch.maxHeight + Tokens.spacing.extraLarge * 2

    // Without this the whole (mostly transparent) surface swallows clicks
    // meant for whatever is underneath it, exactly as BarWindow documents.
    // Region tracks `notch`'s animating bounds via set_input_region, a
    // plain surface commit -- it does not resize the layer surface.
    mask: Region {
        item: notch
    }

    Notch {
        id: notch

        anchors.horizontalCenter: parent.horizontalCenter
        y: Tokens.spacing.extraSmall
    }
}
