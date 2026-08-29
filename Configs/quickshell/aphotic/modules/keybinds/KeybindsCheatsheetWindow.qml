pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services

// SUPER+K cheatsheet -- every hyprctl-reported bind with a description
// (HyprKeybinds.qml), grouped into a small set of heuristic categories
// and laid out as one scrollable column. Same PanelWindow/click-outside/
// Escape-to-close shape as SettingsWindow.qml, so it reads as the same
// kind of surface rather than a one-off.
PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    required property ScreenState screenState

    WlrLayershell.namespace: "aphotic-keybinds"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    visible: screenState.keybindsCheatsheet
    implicitWidth: screen.width
    implicitHeight: screen.height

    onVisibleChanged: {
        if (visible)
            HyprKeybinds.refresh();
    }

    MouseArea {
        anchors.fill: parent
        focus: true
        onClicked: root.screenState.keybindsCheatsheet = false

        Keys.onEscapePressed: root.screenState.keybindsCheatsheet = false
    }

    StyledClippingRect {
        id: sheet

        anchors.centerIn: parent
        width: 900
        height: 780
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer
        border.width: Config.border.thickness
        border.color: Colours.palette.m3outlineVariant

        // Swallow clicks on the sheet itself so they don't fall through
        // to the full-screen MouseArea behind it and close the sheet.
        MouseArea {
            anchors.fill: parent
        }

        DepthGradient {
            anchors.fill: parent
            radius: sheet.radius
            baseColour: sheet.color
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.extraLarge
            spacing: Tokens.spacing.large

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "keyboard"
                    fontStyle: Tokens.font.icon.large
                    color: Colours.palette.m3primary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Keybinds")
                    font: Tokens.font.title.large
                }

                StyledText {
                    text: qsTr("%1 binds").arg(HyprKeybinds.entries.length)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }

                StyledRect {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Tokens.rounding.full
                    color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "close"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.screenState.keybindsCheatsheet = false
                    }
                }
            }

            Flickable {
                id: sheetFlick

                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: columnContent.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ColumnLayout {
                    id: columnContent

                    width: sheetFlick.width
                    spacing: Tokens.spacing.largeIncreased

                    Repeater {
                        model: HyprKeybinds.categorizedEntries

                        ColumnLayout {
                            id: group

                            required property var modelData

                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            StyledText {
                                text: group.modelData.category
                                color: Colours.palette.m3primary
                                font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
                            }

                            StyledRect {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: Colours.palette.m3outlineVariant
                                opacity: 0.5
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: Tokens.spacing.medium
                                rowSpacing: Tokens.spacing.extraSmall

                                Repeater {
                                    model: group.modelData.items

                                    RowLayout {
                                        id: bindRow

                                        required property var modelData

                                        Layout.fillWidth: true
                                        spacing: Tokens.spacing.medium

                                        StyledRect {
                                            Layout.preferredWidth: comboText.implicitWidth + Tokens.padding.medium * 2
                                            Layout.preferredHeight: comboText.implicitHeight + Tokens.padding.extraSmall * 2
                                            radius: Tokens.rounding.small
                                            color: Colours.tPalette.m3surfaceContainer

                                            StyledText {
                                                id: comboText
                                                anchors.centerIn: parent
                                                text: bindRow.modelData.combo
                                                font: Tokens.font.mono.small
                                                color: Colours.palette.m3onSurfaceVariant
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: bindRow.modelData.description
                                            font: Tokens.font.body.medium
                                            color: Colours.palette.m3onSurface
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
