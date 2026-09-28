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

    visible: reveal.active && !Surfaces.suppressed
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

    Rectangle {
        anchors.fill: parent
        color: Colours.palette.m3shadow
        opacity: reveal.visibleProgress * 0.45
    }

    SurfaceReveal {
        id: reveal

        anchors.centerIn: parent
        shown: root.screenState.keybindsCheatsheet
        edge: "bottom"

        Elevation {
            target: sheet
            level: Settings.barSignal ? 2 : 3
        }

        StyledClippingRect {
            id: sheet

            width: 900
            height: 780
            radius: Tokens.rounding.extraLarge
            color: Settings.barSignal ? Colours.signalStyle.glass : Colours.tPalette.m3surfaceContainer
            border.width: Settings.barSignal ? 1 : Config.border.thickness
            border.color: Settings.barSignal ? Colours.signalStyle.hairline : Colours.palette.m3outlineVariant

            // Swallow clicks on the sheet itself so they don't fall through
            // to the full-screen MouseArea behind it and close the sheet.
            MouseArea {
                anchors.fill: parent
            }

            DepthGradient {
                anchors.fill: parent
                radius: sheet.radius
                baseColour: sheet.color
                visible: !Settings.barSignal
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

                            StyledRect {
                                id: group

                                required property var modelData
                                required property int index

                                readonly property bool signalSkin: Settings.barSignal
                                readonly property color tint: Colours.signalStyle.tint(index)

                                Layout.fillWidth: true
                                implicitHeight: groupLayout.implicitHeight + (signalSkin ? Tokens.padding.medium * 2 : 0)
                                radius: signalSkin ? Tokens.rounding.medium : 0
                                color: signalSkin ? Colours.signalStyle.raised : "transparent"
                                border.width: signalSkin ? 1 : 0
                                border.color: signalSkin ? Colours.signalStyle.hairline : "transparent"

                                Elevation {
                                    visible: signalSkin
                                    target: group
                                    level: 1
                                }

                                Rectangle {
                                    visible: signalSkin
                                    x: group.radius
                                    width: group.width - group.radius * 2
                                    height: 1
                                    color: Colours.signalStyle.edgeLight
                                }

                                ColumnLayout {
                                    id: groupLayout

                                    anchors.fill: parent
                                    anchors.margins: group.signalSkin ? Tokens.padding.medium : 0
                                    spacing: group.signalSkin ? Tokens.spacing.medium : Tokens.spacing.small

                                    RowLayout {
                                        visible: group.signalSkin
                                        Layout.fillWidth: true
                                        spacing: Tokens.spacing.small

                                        Rectangle {
                                            Layout.preferredWidth: 6
                                            Layout.preferredHeight: 6
                                            radius: 3
                                            color: group.tint
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: group.modelData.category.toUpperCase()
                                            color: Colours.palette.m3onSurfaceVariant
                                            font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
                                        }
                                    }

                                    StyledText {
                                        visible: !group.signalSkin
                                        text: group.modelData.category
                                        color: Colours.palette.m3primary
                                        font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
                                    }

                                    StyledRect {
                                        visible: !group.signalSkin
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
                                                required property int index

                                                readonly property bool signalSkin: Settings.barSignal
                                                readonly property real staggerIn: index < 8 ? reveal.staggered(index) : 1

                                                Layout.fillWidth: true
                                                spacing: Tokens.spacing.medium
                                                opacity: bindRow.staggerIn
                                                transform: Translate {
                                                    y: (1 - bindRow.staggerIn) * Tokens.spacing.large
                                                }

                                                StyledRect {
                                                    Layout.preferredWidth: comboText.implicitWidth + Tokens.padding.medium * 2
                                                    Layout.preferredHeight: comboText.implicitHeight + Tokens.padding.extraSmall * 2
                                                    radius: bindRow.signalSkin ? Tokens.rounding.full : Tokens.rounding.small
                                                    color: bindRow.signalSkin ? Colours.signalStyle.raisedHi : Colours.tPalette.m3surfaceContainer
                                                    border.width: bindRow.signalSkin ? 1 : 0
                                                    border.color: bindRow.signalSkin ? Colours.signalStyle.hairline : "transparent"

                                                    StyledText {
                                                        id: comboText
                                                        anchors.centerIn: parent
                                                        text: bindRow.modelData.combo
                                                        font: bindRow.signalSkin ? Tokens.font.mono.builders.small.weight(Font.DemiBold).build() : Tokens.font.mono.small
                                                        color: Colours.palette.m3onSurfaceVariant
                                                    }
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: bindRow.modelData.description
                                                    font: Tokens.font.body.medium
                                                    color: bindRow.signalSkin ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
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
    }
}
