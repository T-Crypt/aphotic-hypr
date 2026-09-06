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
    property int hoveredIndex: -1

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

            width: 216
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
                    height: navigationRepeater.count * 48

                    readonly property int activeIndex: Math.max(0, root.workspace.findIndex(surface => surface.id === root.activeId))

                    StyledRect {
                        x: 0
                        y: navigationList.activeIndex * 48
                        width: parent.width
                        height: 44
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3primary

                        Behavior on y {
                            SpringAnimation {
                                spring: 4
                                damping: 0.62
                                mass: 0.9
                                epsilon: 0.25
                            }
                        }
                    }

                    StyledRect {
                        x: 0
                        y: Math.max(0, root.hoveredIndex) * 48
                        width: parent.width
                        height: 44
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3onSurface
                        opacity: root.hoveredIndex >= 0 && root.hoveredIndex !== navigationList.activeIndex ? 0.08 : 0

                        Behavior on y { Anim { type: Anim.FastEffects } }
                        Behavior on opacity { Anim { type: Anim.FastEffects } }
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
                            y: navItem.index * 48
                            width: navigationList.width
                            height: 44

                            StateLayer {
                                anchors.fill: parent
                                radius: Tokens.rounding.medium
                                stateOpacity: 0
                                onClicked: root.activeId = navItem.modelData.id
                                onContainsMouseChanged: {
                                    if (containsMouse)
                                        root.hoveredIndex = navItem.index;
                                    else if (root.hoveredIndex === navItem.index)
                                        root.hoveredIndex = -1;
                                }
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.padding.small
                                anchors.rightMargin: Tokens.padding.small
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: navItem.modelData.icon
                                    color: navItem.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                                    fontStyle: Tokens.font.icon.small
                                    fill: navItem.active ? 1 : 0
                                    Behavior on color { CAnim {} }
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 32
                                    elide: Text.ElideRight
                                    text: navItem.modelData.label
                                    font: Tokens.font.label.builders.medium.weight(navItem.active ? Font.Medium : Font.Normal).build()
                                    color: navItem.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurface
                                    Behavior on color { CAnim {} }
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
                anchors.fill: parent
                active: root.surfaceActive && root.activeSurface !== null
                asynchronous: true
                source: root.activeSurface?.componentUrl ?? ""
            }
        }
    }
}
