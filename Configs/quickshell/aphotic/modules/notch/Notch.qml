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
        Slot2,
        Slot3,
        Slot4
    }

    // Three reserved slots, named for what they are rather than for
    // content nobody has written: identical "Reserved" labels would make
    // the one thing this strip exists to demonstrate -- that you can tell
    // where you are and move between four of them -- impossible to see.
    readonly property var tiles: [
        {
            tile: Notch.Processes,
            icon: "monitoring",
            label: qsTr("Processes")
        },
        {
            tile: Notch.Slot2,
            icon: "terminal",
            label: qsTr("Slot 2")
        },
        {
            tile: Notch.Slot3,
            icon: "hub",
            label: qsTr("Slot 3")
        },
        {
            tile: Notch.Slot4,
            icon: "extension",
            label: qsTr("Slot 4")
        }
    ]

    readonly property var activeTile: root.tiles.find(t => t.tile === root.shownTile) ?? null
    readonly property bool processesLive: root.expanded && root.shownTile === Notch.Processes

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
    // NOT Tokens.rounding.full for the collapsed pill: that is 999999, and
    // animating it down to a real radius keeps the value above width/2
    // (where every value renders identically) until the last few frames,
    // then drops through the whole visible range at once -- a snap at the
    // end of an otherwise smooth grow. Half the collapsed height is the
    // same pill, expressed as a number the Behavior can actually traverse.
    radius: root.expanded ? Tokens.rounding.large : Config.notch.collapsedHeight / 2
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
        active: root.processesLive

        ProcessUsageWatch {}
    }

    // Gated here rather than mounted inside NotchProcessTile: the tile
    // outlives a collapse (shownTile latches so the body still reports a
    // height through the shrink), so a watch owned by the tile would keep
    // polling for as long as Processes was the last tile visited. Both
    // watches hang off the same gate for that reason.
    LazyLoader {
        active: root.processesLive

        SystemUsageWatch {
            fast: true
        }
    }

    // The body is laid out at a constant contentWidth (see above) while the
    // surface around it animates from the collapsed pill's 132px -- so for
    // the first part of every open it is a 388px-wide layout being drawn
    // into a box a third that size. Fading it in on its own short curve
    // meant it arrived at full opacity while still mostly clipped, which
    // is the "glitchy on the open" it read as. Holding the reveal until
    // the geometry has covered most of the distance means content only
    // appears once there is room for it. 150ms is measured, not guessed:
    // Anim.Emphasized front-loads hard enough that a nominally 500ms run
    // is already at ~400 of its 420px by then. Collapse takes
    // the other path: revealed goes false immediately, so the body is gone
    // before the box starts shrinking under it.
    property bool revealed: false

    Timer {
        id: revealTimer
        interval: 150
        onTriggered: root.revealed = true
    }

    onExpandedChanged: {
        if (root.expanded) {
            revealTimer.restart();
        } else {
            revealTimer.stop();
            root.revealed = false;
        }
    }

    // Faded rather than flipped straight to invisible: the click that
    // opens the notch starts a ripple that runs 600ms, longer than the
    // 500ms expand, so hiding this the instant `expanded` flips cut the
    // ripple off mid-sweep and read as a flash under the growing box.
    StateLayer {
        radius: root.radius
        disabled: root.expanded
        visible: opacity > 0
        opacity: root.expanded ? 0 : 1
        onClicked: root.cycle()

        Behavior on opacity {
            Anim { type: Anim.FastEffects }
        }
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

            // Centred, not pinned at the padding origin: while the surface
            // is still growing the clip has to cut something off, and
            // taking it evenly off both edges reads as the box opening
            // around the content rather than the content sliding in from
            // one side.
            anchors.centerIn: parent
            width: root.contentWidth
            spacing: Tokens.spacing.small
            visible: opacity > 0
            opacity: root.revealed ? 1 : 0

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
                            text: root.activeTile?.icon ?? "monitoring"
                            color: Colours.palette.m3primaryOnSurface
                            fontStyle: Tokens.font.icon.small
                            fill: 1
                        }

                        StyledText {
                            id: title

                            text: root.activeTile?.label ?? ""
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

                sourceComponent: root.shownTile === Notch.Processes ? processComp : placeholderComp
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

                        implicitWidth: chipLabel.implicitWidth + chipIcon.implicitWidth + Tokens.padding.small * 2 + Tokens.spacing.extraSmall
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
        NotchPlaceholderTile {
            slotLabel: root.activeTile?.label ?? ""
            slotIcon: root.activeTile?.icon ?? "extension"
        }
    }
}
