pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs.config
import qs.components
import qs.services

StyledRect {
    id: root

    enum Tile {
        Idle = 0,
        Processes,
        Placeholder
    }

    readonly property var tiles: [
        {
            tile: Notch.Processes,
            icon: "monitoring",
            label: qsTr("Processes")
        },
        {
            tile: Notch.Placeholder,
            icon: "extension",
            label: qsTr("Reserved")
        }
    ]

    property int tile: Notch.Idle
    readonly property bool expanded: root.tile !== Notch.Idle

    // Which tile the expanded body is BUILT for, kept latched past a
    // collapse so the body still reports a real implicitHeight while the
    // height animation plays -- reading it off `tile` instead would
    // collapse the target to zero on the first frame and cut the
    // animation short. Same reasoning as popouts/Wrapper.qml's
    // showContent.
    property int shownTile: Notch.Processes

    readonly property real contentWidth: Config.notch.expandedWidth - Tokens.padding.large * 2

    function cycle(): void {
        const i = root.tiles.findIndex(t => t.tile === root.tile);
        root.tile = root.tiles[(i + 1) % root.tiles.length].tile;
    }

    function collapse(): void {
        root.tile = Notch.Idle;
    }

    onTileChanged: {
        if (root.tile !== Notch.Idle)
            root.shownTile = root.tile;
    }

    // Only the inner surface moves. Every dimension here is either a
    // constant or driven by content that is itself laid out at a constant
    // width (see contentWidth), so nothing feeds back into the enclosing
    // PanelWindow's geometry.
    width: root.expanded ? Config.notch.expandedWidth : Config.notch.collapsedWidth
    height: root.expanded ? Math.min(body.implicitHeight + Tokens.padding.medium * 2, Config.notch.maxHeight) : Config.notch.collapsedHeight
    radius: root.expanded ? Tokens.rounding.large : Tokens.rounding.full
    color: Colours.palette.m3surfaceContainerHigh

    Behavior on width {
        Anim { type: Anim.Emphasized }
    }
    Behavior on height {
        Anim { type: Anim.Emphasized }
    }
    Behavior on radius {
        Anim { type: Anim.Emphasized }
    }

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Colours.palette.m3shadow
        shadowOpacity: 0.5
        shadowBlur: 0.5
        shadowVerticalOffset: 2
    }

    LazyLoader {
        active: root.expanded && root.shownTile === Notch.Processes

        ProcessUsageWatch {}
    }

    StateLayer {
        radius: root.radius
        disabled: root.expanded
        visible: !root.expanded
        onClicked: root.cycle()
    }

    component MicroBar: StyledRect {
        id: microBar

        property real perc: 0
        property color barColour: Colours.palette.m3primary

        implicitWidth: 34
        implicitHeight: 4
        radius: Tokens.rounding.full
        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

        StyledRect {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * Math.max(0, Math.min(1, microBar.perc))
            radius: Tokens.rounding.full
            color: microBar.barColour
        }
    }

    Item {
        anchors.fill: parent
        clip: true

        // Idle deliberately carries no clock: the bar already owns one in
        // every style that shows the time (Bar/TaskbarBar/DockBar's Clock,
        // MinimalBar's inline string), and a second one two centimetres
        // away is just a duplicate. What is left is the smallest useful
        // affordance -- live CPU and memory, off SystemUsage's
        // always-running base poll, so idle costs nothing extra.
        RowLayout {
            id: idle

            anchors.centerIn: parent
            spacing: Tokens.spacing.small
            visible: opacity > 0
            opacity: root.expanded ? 0 : 1

            Behavior on opacity {
                Anim { type: Anim.FastEffects }
            }

            MaterialIcon {
                text: "monitoring"
                color: Colours.palette.m3primaryOnSurface
                fontStyle: Tokens.font.icon.small
                fill: 1
            }

            MicroBar {
                perc: SystemUsage.cpuPerc
                barColour: Colours.palette.m3primary
            }

            MicroBar {
                perc: SystemUsage.memPerc
                barColour: Colours.palette.m3tertiary
            }
        }

        ColumnLayout {
            id: body

            x: Tokens.padding.large
            y: Tokens.padding.medium
            width: root.contentWidth
            spacing: Tokens.spacing.small
            visible: opacity > 0
            opacity: root.expanded ? 1 : 0

            Behavior on opacity {
                Anim { type: Anim.DefaultEffects }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: title.implicitHeight + Tokens.padding.extraSmall * 2
                    radius: Tokens.rounding.small
                    color: "transparent"

                    StateLayer {
                        radius: parent.radius
                        disabled: !root.expanded
                        onClicked: root.cycle()
                    }

                    RowLayout {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: root.tiles.find(t => t.tile === root.shownTile)?.icon ?? "monitoring"
                            color: Colours.palette.m3primaryOnSurface
                            fontStyle: Tokens.font.icon.small
                            fill: 1
                        }

                        StyledText {
                            id: title

                            text: root.tiles.find(t => t.tile === root.shownTile)?.label ?? ""
                            font: Tokens.font.title.builders.medium.weight(Font.Medium).build()
                        }
                    }
                }

                StyledRect {
                    implicitWidth: 24
                    implicitHeight: 24
                    radius: Tokens.rounding.full
                    color: "transparent"

                    StateLayer {
                        radius: parent.radius
                        disabled: !root.expanded
                        onClicked: root.collapse()
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "keyboard_arrow_up"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }
                }
            }

            Loader {
                id: tileLoader

                Layout.fillWidth: true
                Layout.preferredHeight: tileLoader.item?.implicitHeight ?? 0

                sourceComponent: root.shownTile === Notch.Placeholder ? placeholderComp : processComp
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.extraSmall
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    model: root.tiles

                    StyledRect {
                        id: chip

                        required property var modelData
                        readonly property bool active: chip.modelData.tile === root.shownTile

                        implicitWidth: chipLabel.implicitWidth + chipIcon.implicitWidth + Tokens.padding.medium * 2 + Tokens.spacing.extraSmall
                        implicitHeight: 26
                        radius: Tokens.rounding.full
                        color: chip.active ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

                        Behavior on color {
                            CAnim {}
                        }

                        StateLayer {
                            radius: parent.radius
                            disabled: !root.expanded
                            onClicked: root.tile = chip.modelData.tile
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: Tokens.spacing.extraSmall

                            MaterialIcon {
                                id: chipIcon

                                text: chip.modelData.icon
                                color: chip.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.small
                                fill: chip.active ? 1 : 0
                            }

                            StyledText {
                                id: chipLabel

                                text: chip.modelData.label
                                color: chip.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.builders.small.weight(Font.Medium).build()
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }

    Component {
        id: processComp
        NotchProcessTile {}
    }
    Component {
        id: placeholderComp
        NotchPlaceholderTile {}
    }
}
