// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services

// The ALT+Tab surface. Reads Switcher and never writes to it except
// through the same functions the keybinds call, so a click and a
// keystroke go down one path.
//
// Deliberately takes no keyboard focus. Hyprland is in a submap for as
// long as this is up (Configs/hypr/keybinds.lua), which means it, not
// this window, sees the ALT release -- and a layer surface that grabbed
// the keyboard mid-chord would have to guess at a key it never saw
// pressed.
PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    // One monitor shows the switcher: the one that was focused when it
    // opened. The others stay as they are rather than each drawing their
    // own copy of the same snapshot.
    visible: Switcher.open && Switcher.monitorName === (Hypr.monitorFor(root.modelData)?.name ?? "")

    WlrLayershell.namespace: "aphotic-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    implicitWidth: screen.width
    implicitHeight: screen.height

    // Cards are sized to fill the panel's width rather than to a fixed
    // height, so two workspaces get big readable previews and eight
    // still fit on one line without a scrollbar.
    readonly property real panelWidth: Math.min(root.width - Tokens.padding.extraExtraLarge * 2, 1500)
    readonly property real cardsWidth: root.panelWidth - Tokens.padding.extraLarge * 2
    readonly property real aspectSum: Switcher.cards.reduce((sum, c) => sum + c.rect.width / c.rect.height, 0)
    readonly property real cardHeight: {
        const n = Switcher.cards.length;
        if (n === 0 || root.aspectSum <= 0)
            return 0;
        const spacing = Tokens.spacing.medium * (n - 1);
        return Math.min(240, (root.cardsWidth - spacing) / root.aspectSum);
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Switcher.close()
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3shadow, 0.55)
    }

    StyledClippingRect {
        id: panel

        anchors.centerIn: parent
        width: root.panelWidth
        implicitHeight: content.implicitHeight + Tokens.padding.extraLarge * 2
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer
        border.width: Config.border.thickness
        border.color: Colours.palette.m3outlineVariant

        // Swallow clicks on the panel so they don't reach the
        // cancel-on-click-outside handler behind it.
        MouseArea {
            anchors.fill: parent
        }

        DepthGradient {
            anchors.fill: parent
            radius: panel.radius
            baseColour: panel.color
        }

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.padding.extraLarge
            spacing: Tokens.spacing.large

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "swap_horiz"
                    fontStyle: Tokens.font.icon.large
                    color: Colours.palette.m3primary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Switch window")
                    font: Tokens.font.title.large
                }

                StyledText {
                    text: qsTr("%n window(s)", "", Switcher.windows.length)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.spacing.medium

                Repeater {
                    model: Switcher.cards

                    WorkspaceCard {
                        required property var modelData

                        card: modelData
                        cardHeight: root.cardHeight
                        active: Switcher.currentWorkspace === modelData.id
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                AppIcon {
                    visible: !!Switcher.current
                    appClass: Switcher.current?.appClass ?? ""
                    size: 24
                }

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font: Tokens.font.body.large
                    text: Switcher.current ? Switcher.current.title : qsTr("Workspace %1").arg(Switcher.selectedWorkspace)
                }

                StyledText {
                    text: Switcher.current ? Switcher.current.appClass : qsTr("empty desktop")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                text: qsTr("Tab cycle  ·  A-; workspace  ·  1-9 window  ·  arrows move  ·  release Alt to switch  ·  Esc cancel")
            }
        }
    }
}
