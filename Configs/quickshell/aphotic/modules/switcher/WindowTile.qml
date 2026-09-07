// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services

// One window, drawn where it actually sits on its monitor. The parent
// card hands over the scale factor; everything here is that scale
// applied to the rectangle Hyprland reported at snapshot time, so the
// preview is the desktop rather than a list pretending to be one.
StyledRect {
    id: root

    required property var win
    required property var rect
    required property real scale
    required property int badge
    required property bool selected

    x: (root.win.x - root.rect.x) * root.scale
    y: (root.win.y - root.rect.y) * root.scale
    width: Math.max(18, root.win.width * root.scale)
    height: Math.max(14, root.win.height * root.scale)

    radius: Tokens.rounding.small
    color: root.selected ? Qt.alpha(Colours.palette.m3primary, 0.28) : Colours.layer(Colours.palette.m3surfaceContainer, 2)
    border.width: root.selected ? 2 : 1
    border.color: root.selected ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

    AppIcon {
        anchors.centerIn: parent
        appClass: root.win.appClass
        size: Math.max(14, Math.min(28, Math.min(root.width, root.height) * 0.45))
        colour: Colours.palette.m3onSurface
    }

    // Only nine badges exist, so a card with more windows than that
    // stops numbering rather than showing keys that do nothing.
    StyledRect {
        visible: root.badge > 0 && root.badge <= 9
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 3
        width: 15
        height: 15
        radius: Tokens.rounding.full
        color: root.selected ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3surfaceContainer, 3)

        StyledText {
            anchors.centerIn: parent
            text: root.badge
            color: root.selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: Switcher.selectAddress(root.win.address)
        onClicked: {
            Switcher.selectAddress(root.win.address);
            Switcher.commit();
        }
    }
}
