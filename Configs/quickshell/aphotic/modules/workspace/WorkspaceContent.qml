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

    function _revealPane(): void {
        paneFade.stop();
        paneTravel.stop();
        paneLoader.opacity = 0;
        paneLoader.y = Tokens.spacing.medium;
        paneFade.start();
        paneTravel.start();
    }

    Component.onCompleted: root._ensureActive()
    onWorkspaceChanged: root._ensureActive()

    Elevation {
        target: frame
        level: 3
    }

    StyledRect {
        id: frame

        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

        StyledRect {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, parent.radius - 1)
            color: Colours.palette.m3surfaceContainer
        }
    }

    Row {
        anchors.fill: parent
        anchors.margins: Tokens.spacing.medium
        spacing: Tokens.spacing.medium

        StyledRect {
            id: navigation

            width: Tokens.sizes.workspace.railWidth
            height: parent.height
            radius: Tokens.rounding.large
            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
            clip: true

            Column {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.extraSmall

                Item {
                    width: parent.width
                    height: 58

                    StyledRect {
                        width: 34
                        height: 34
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3primary

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "space_dashboard"
                            color: Colours.contrastOn(Colours.palette.m3primary)
                            fontStyle: Tokens.font.icon.medium
                            fill: 1
                        }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 44
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 44
                        spacing: 1

                        StyledText {
                            text: qsTr("Workspace")
                            font: Tokens.font.title.small
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            text: qsTr("Plugin tools")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    topPadding: Tokens.spacing.small
                    bottomPadding: Tokens.spacing.extraSmall
                    text: qsTr("AVAILABLE")
                    font: Tokens.font.label.builders.small.weight(Font.Medium).build()
                    color: Colours.palette.m3onSurfaceVariant
                }

                Item {
                    id: navigationList

                    width: parent.width
                    height: navigationRepeater.count * Tokens.sizes.workspace.itemHeight

                    readonly property int activeIndex: Math.max(0, root.workspace.findIndex(surface => surface.id === root.activeId))

                    StyledRect {
                        x: 0
                        y: navigationList.activeIndex * Tokens.sizes.workspace.itemHeight
                        width: parent.width
                        height: Tokens.sizes.workspace.itemHeight
                        radius: Tokens.rounding.medium
                        color: Qt.alpha(Colours.palette.m3primary, 0.14)

                        Behavior on y { Anim { type: Anim.DefaultSpatial } }

                        StyledRect {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: parent.height - Tokens.spacing.large
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3primary
                        }
                    }

                    Repeater {
                        id: navigationRepeater
                        model: root.workspace

                        Item {
                            id: navItem

                            required property var modelData
                            required property int index
                            readonly property bool active: root.activeId === navItem.modelData.id

                            x: 0
                            y: navItem.index * Tokens.sizes.workspace.itemHeight
                            width: navigationList.width
                            height: Tokens.sizes.workspace.itemHeight

                            StateLayer {
                                anchors.fill: parent
                                radius: Tokens.rounding.medium
                                onClicked: root.activeId = navItem.modelData.id
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.padding.small
                                anchors.rightMargin: Tokens.padding.small
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: navItem.modelData.icon
                                    color: navItem.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                    fontStyle: Tokens.font.icon.small
                                    fill: navItem.active ? 1 : 0
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 32
                                    elide: Text.ElideRight
                                    text: navItem.modelData.label
                                    font: Tokens.font.label.builders.medium.weight(navItem.active ? Font.Medium : Font.Normal).build()
                                    color: navItem.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }
        }

        StyledRect {
            width: parent.width - navigation.width - parent.spacing
            height: parent.height
            radius: Tokens.rounding.large
            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 1)
            clip: true

            Loader {
                id: paneLoader

                x: 0
                y: 0
                width: parent.width
                height: parent.height

                active: root.surfaceActive && root.activeSurface !== null
                asynchronous: true
                opacity: 0
                source: root.activeSurface?.componentUrl ?? ""

                onStatusChanged: {
                    if (paneLoader.status === Loader.Ready)
                        root._revealPane();
                }
            }

            Anim {
                id: paneFade

                alwaysRunToEnd: true
                target: paneLoader
                property: "opacity"
                from: 0
                to: 1
                type: Anim.FastEffects
            }

            Anim {
                id: paneTravel

                alwaysRunToEnd: true
                target: paneLoader
                property: "y"
                from: Tokens.spacing.medium
                to: 0
                type: Anim.FastSpatial
            }

            Column {
                anchors.centerIn: parent
                spacing: Tokens.spacing.small
                visible: paneLoader.item === null

                MaterialIcon {
                    text: "widgets"
                    color: Colours.palette.m3onSurfaceVariant
                    opacity: 0.5
                    fontStyle: Tokens.font.icon.large
                }

                StyledText {
                    text: qsTr("No plugin surfaces")
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
}
