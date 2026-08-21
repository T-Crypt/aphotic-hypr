pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.utils

GridLayout {
    id: root

    required property ScreenState screenState

    columns: 4
    columnSpacing: Tokens.spacing.medium
    rowSpacing: Tokens.spacing.medium

    Repeater {
        model: ScriptModel {
            values: Hypr.workspaces.values.slice().sort((a, b) => a.id - b.id)
        }

        StyledRect {
            id: wsCard

            required property var modelData
            readonly property bool active: wsCard.modelData.id === Hypr.activeWsId
            readonly property var windows: Hypr.toplevels.values.filter(c => c.workspace?.id === wsCard.modelData.id)

            Layout.preferredWidth: 140
            Layout.preferredHeight: 100
            radius: Tokens.rounding.large
            color: wsCard.active ? Colours.layer(Colours.tPalette.m3surfaceContainer, 2) : Colours.tPalette.m3surfaceContainer
            border.width: wsCard.active ? 2 : 0
            border.color: Colours.palette.m3primary

            Behavior on color {
                CAnim {}
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                StyledText {
                    text: wsCard.modelData.id
                    color: wsCard.active ? Colours.palette.m3primary : Colours.palette.m3onSurface
                    font: Tokens.font.title.builders.medium.weight(Font.Medium).build()
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: wsCard.windows.slice(0, 9)

                        MaterialIcon {
                            required property var modelData

                            text: Icons.getAppCategoryIcon(modelData.lastIpcObject.class, "desktop_windows")
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small
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
