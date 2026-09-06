pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.config
import qs.services

Item {
    id: root

    readonly property var workspace: PluginRegistry.surfacesFor("workspace").slice().sort((a, b) => a.label.localeCompare(b.label))
    readonly property var activeSurface: root.workspace.find(surface => surface.id === root.activeId) ?? null
    property string activeId: ""
    property bool surfaceActive: false

    function _ensureActive(): void {
        if (root.workspace.some(surface => surface.id === root.activeId))
            return;
        root.activeId = root.workspace[0]?.id ?? "";
    }

    Component.onCompleted: root._ensureActive()
    onWorkspaceChanged: root._ensureActive()

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer
    }

    Row {
        anchors.fill: parent
        anchors.margins: Tokens.spacing.large
        spacing: Tokens.spacing.large

        Column {
            width: 184
            spacing: Tokens.spacing.small

            StyledText {
                text: qsTr("Workspace")
                font: Tokens.font.title.medium
                color: Colours.palette.m3onSurface
            }

            Repeater {
                model: root.workspace

                delegate: Rectangle {
                    required property var modelData
                    width: 184
                    height: 48
                    radius: Tokens.rounding.normal
                    color: root.activeId === modelData.id ? Colours.palette.m3secondaryContainer : "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacing.small
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.icon
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 32
                            elide: Text.ElideRight
                            text: modelData.label
                            color: Colours.palette.m3onSurface
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.activeId = parent.modelData.id
                    }
                }
            }
        }

        Item {
            width: parent.width - 184 - parent.spacing
            height: parent.height

            Loader {
                anchors.fill: parent
                active: root.surfaceActive && root.activeSurface !== null
                asynchronous: true
                source: root.activeSurface?.componentUrl ?? ""
            }
        }
    }
}
