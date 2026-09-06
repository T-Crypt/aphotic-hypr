// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// The command palette: the user's own slots, in their own order, over
// ACT-01's action list. Core tile, like Processes -- every install has
// one, and what is in it is a settings question, not an install question.
//
// This file knows no action's id. It renders Settings.paletteEntries
// against whatever Actions.actions currently resolves, so a plugin's
// action appears here the moment that plugin is installed and disappears
// again when it is removed, with no edit anywhere.
ColumnLayout {
    id: root

    // A slot whose action does not resolve is dropped from the tile
    // rather than drawn dead, and kept in settings.json regardless -- see
    // Settings.paletteEntries. Disabling a plugin for an afternoon should
    // empty a row, not delete it.
    readonly property var rows: Settings.paletteEntries.filter(e => e.enabled && Actions.has(e.id)).map(e => Actions.find(e.id))

    signal invoked

    required property var screenState

    spacing: Tokens.spacing.extraSmall

    StyledText {
        Layout.fillWidth: true
        Layout.bottomMargin: Tokens.spacing.extraSmall
        visible: root.rows.length === 0
        wrapMode: Text.WordWrap
        text: qsTr("No actions yet. Settings › Bar › Command palette picks what lands here.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
    }

    Repeater {
        model: root.rows

        StyledRect {
            id: actionRow

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: 32
            radius: Tokens.rounding.small
            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

            StateLayer {
                radius: parent.radius
                onClicked: {
                    Actions.invoke(actionRow.modelData.id, {
                        screenState: root.screenState
                    });
                    root.invoked();
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.small
                anchors.rightMargin: Tokens.padding.small
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: actionRow.modelData.icon
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: actionRow.modelData.label
                    elide: Text.ElideRight
                    font: Tokens.font.body.medium
                }

                // Says an action came from a plugin without naming which
                // one: the label is the plugin's own words already, and a
                // second copy of the plugin name in every row is noise.
                MaterialIcon {
                    visible: actionRow.modelData.plugin.length > 0
                    text: "extension"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }
            }
        }
    }
}
