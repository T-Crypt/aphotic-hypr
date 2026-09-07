// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services

// One workspace as a miniature of its own monitor, at that monitor's
// real aspect ratio -- an ultrawide reads as an ultrawide next to a
// 16:9, which is the only way the window outlines inside mean anything.
StyledClippingRect {
    id: root

    required property var card
    required property real cardHeight
    required property bool active

    readonly property real scale: root.cardHeight / root.card.rect.height

    implicitHeight: root.cardHeight
    implicitWidth: Math.round(root.card.rect.width * root.scale)

    radius: Tokens.rounding.large
    color: Colours.layer(Colours.tPalette.m3surfaceContainer, 1)
    border.width: root.active ? 2 : Config.border.thickness
    border.color: root.active ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

    Repeater {
        model: root.card.windows

        WindowTile {
            required property var modelData
            required property int index

            win: modelData
            rect: root.card.rect
            scale: root.scale
            badge: index + 1
            selected: Switcher.current === modelData
        }
    }

    // The home-row key, in the corner, on the card it lands on. Nothing
    // else in the surface teaches which key goes where.
    StyledRect {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: Tokens.padding.small
        implicitWidth: keyLabel.implicitWidth + Tokens.padding.medium
        implicitHeight: keyLabel.implicitHeight + Tokens.padding.extraSmall
        radius: Tokens.rounding.small
        visible: root.card.key.length > 0
        color: root.active ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

        StyledText {
            id: keyLabel

            anchors.centerIn: parent
            text: `${root.card.key.toUpperCase()}  ·  ${root.card.id}`
            color: root.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.card.windows.length === 0
        text: qsTr("empty")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    // Selecting the card itself is what picks an empty desktop; on a
    // populated one the tiles above take the click first.
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: Switcher.selectWorkspace(root.card.id)
        onDoubleClicked: {
            Switcher.selectWorkspace(root.card.id);
            Switcher.commit();
        }
    }
}
