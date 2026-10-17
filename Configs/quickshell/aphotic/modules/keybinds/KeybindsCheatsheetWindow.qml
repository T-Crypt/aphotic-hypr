pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services

// SUPER+K cheatsheet: every bind HyprKeybinds reports, grouped into
// heuristic categories in one scrollable column. Same PanelWindow,
// click-outside and Escape-to-close shape as SettingsWindow.qml.
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
        color: Colours.shadow
        opacity: reveal.visibleProgress * 0.45
    }

    SurfaceReveal {
        id: reveal

        anchors.centerIn: parent
        shown: root.screenState.keybindsCheatsheet
        edge: "bottom"

        Elevation {
            target: sheet
            level: 2
        }

        StyledClippingRect {
            id: sheet

            width: 900
            height: 780
            radius: Tokens.rounding.extraLarge
            color: Colours.signalStyle.glass
            border.width: 1
            border.color: Colours.signalStyle.hairline

            // Swallow clicks on the sheet itself so they don't fall through
            // to the full-screen MouseArea behind it and close the sheet.
            MouseArea {
                anchors.fill: parent
            }

            DepthGradient {
                anchors.fill: parent
                radius: sheet.radius
                baseColour: sheet.color
                visible: false
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
                        color: Colours.signal
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Keybinds")
                        font: Tokens.font.title.large
                    }

                    StyledText {
                        text: qsTr("%1 binds").arg(HyprKeybinds.entries.length)
                        color: Colours.inkMuted
                        font: Tokens.font.label.medium
                    }

                    StyledRect {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: Tokens.rounding.full
                        color: Colours.layer(Colours.surfaceLift, 2)

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "close"
                            color: Colours.inkMuted
                            fontStyle: Tokens.font.icon.small
                        }

                        Interact {
                            anchors.fill: parent
                            radius: parent.radius
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

                            SignalSurface {
                                id: group

                                required property var modelData
                                required property int index

                                readonly property color tint: Colours.signalStyle.tint(index)

                                Layout.fillWidth: true
                                implicitHeight: groupLayout.implicitHeight + Tokens.padding.medium * 2
                                radius: Tokens.rounding.medium
                                tone: Colours.signalStyle.raised

                                Elevation {
                                    target: group
                                    level: 1
                                }

                                ColumnLayout {
                                    id: groupLayout

                                    anchors.fill: parent
                                    anchors.margins: Tokens.padding.medium
                                    spacing: Tokens.spacing.medium

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Tokens.spacing.small

                                        Rectangle {
                                            Layout.preferredWidth: 6
                                            Layout.preferredHeight: 6
                                            radius: Tokens.rounding.full
                                            color: group.tint
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: group.modelData.category.toUpperCase()
                                            color: Colours.inkMuted
                                            font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
                                        }
                                    }

                                    StyledText {
                                        visible: false
                                        text: group.modelData.category
                                        color: Colours.signal
                                        font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
                                    }

                                    StyledRect {
                                        visible: false
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 1
                                        color: Colours.outline
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
                                                    radius: Tokens.rounding.full
                                                    color: Colours.signalStyle.raisedHi
                                                    border.width: 1
                                                    border.color: Colours.signalStyle.hairline

                                                    StyledText {
                                                        id: comboText
                                                        anchors.centerIn: parent
                                                        text: bindRow.modelData.combo
                                                        font: Tokens.font.mono.builders.small.weight(Font.DemiBold).build()
                                                        color: Colours.inkMuted
                                                    }
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: bindRow.modelData.description
                                                    font: Tokens.font.body.medium
                                                    color: Colours.inkMuted
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
