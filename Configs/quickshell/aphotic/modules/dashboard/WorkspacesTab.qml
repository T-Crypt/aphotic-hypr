pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

StyledRect {
    id: root

    required property ScreenState screenState

    readonly property var sortedWorkspaces: Hypr.workspaces.values.slice().sort((a, b) => a.id - b.id)
    readonly property int columns: Math.min(4, Math.max(1, root.sortedWorkspaces.length))

    implicitWidth: grid.implicitWidth + Tokens.padding.large * 2
    implicitHeight: grid.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.extraLarge
    color: Colours.signalStyle.surface

    // The approved dashboard card, with an active state for the live workspace.
    component Card: StyledRect {
        id: card

        property string title: ""
        property int tintIndex: 0
        property bool selected: false
        readonly property real headerHeight: card.title.length > 0 ? cardTitle.implicitHeight + Tokens.padding.medium : 0

        radius: Tokens.rounding.medium
        color: card.selected ? Qt.alpha(Colours.palette.m3primary, 0.08) : Colours.signalStyle.raised
        border.width: 1
        border.color: card.selected ? Colours.signalStyle.accentLine : Colours.signalStyle.hairline

        Elevation {
            target: card
            level: 1
        }

        Rectangle {
            x: card.radius
            width: card.width - card.radius * 2
            height: 1
            color: Colours.signalStyle.edgeLight
        }

        Row {
            id: cardTitle

            visible: card.headerHeight > 0
            x: Tokens.padding.large
            y: Tokens.padding.medium
            spacing: Tokens.spacing.small

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: Colours.signalStyle.tint(card.tintIndex)
            }

            StyledText {
                text: card.title.toUpperCase()
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
            }
        }
    }

    GridLayout {
        id: grid

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large

        columns: root.columns
        columnSpacing: Tokens.spacing.medium
        rowSpacing: Tokens.spacing.medium

        Repeater {
            model: ScriptModel {
                values: root.sortedWorkspaces
            }

            Card {
                id: wsCard

                required property var modelData
                readonly property bool active: wsCard.modelData.id === Hypr.activeWsId
                readonly property var windows: Hypr.toplevels.values.filter(c => c.workspace?.id === wsCard.modelData.id)

                title: qsTr("Workspace %1").arg(wsCard.modelData.id)
                tintIndex: wsCard.modelData.id
                selected: wsCard.active

                Layout.preferredWidth: 140
                Layout.preferredHeight: 100

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    anchors.bottomMargin: Tokens.padding.medium
                    anchors.topMargin: wsCard.headerHeight
                    spacing: Tokens.spacing.small

                    StyledText {
                        visible: false
                        text: wsCard.modelData.id
                        color: wsCard.active ? Colours.legibleAccent(Colours.palette.m3primary, Colours.signalStyle.surface) : Colours.palette.m3onSurface
                        font: Tokens.font.title.builders.medium.weight(Font.Medium).build()
                    }

                    Flow {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Tokens.spacing.small

                        Repeater {
                            model: wsCard.windows.slice(0, 9)

                            Item {
                                id: tile

                                required property var modelData

                                implicitWidth: icon.implicitWidth + Tokens.padding.small
                                implicitHeight: icon.implicitHeight + Tokens.padding.small

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Tokens.rounding.small
                                    color: Colours.signalStyle.raised
                                    border.width: 1
                                    border.color: Colours.signalStyle.hairline
                                }

                                AppIcon {
                                    id: icon

                                    anchors.centerIn: parent
                                    appClass: modelData.lastIpcObject?.class ?? ""
                                    fallbackGlyph: "desktop_windows"
                                    colour: Colours.palette.m3onSurfaceVariant
                                    fontStyle: Tokens.font.icon.small
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: wsCard.windows.length === 0
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("Empty")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: {
                        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = ${wsCard.modelData.id} })` : `workspace ${wsCard.modelData.id}`);
                        root.screenState.dashboard = false;
                    }
                }
            }
        }
    }
}
