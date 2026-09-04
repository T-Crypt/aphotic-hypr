pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services

StyledRect {
    id: root

    required property var tiles
    required property string currentId
    required property var attentionIds
    property bool interactive: true

    signal picked(string id)

    readonly property int count: root.tiles.length
    readonly property int currentIndex: Math.max(0, root.tiles.findIndex(t => t.id === root.currentId))
    property int hoveredIndex: -1

    readonly property real inset: Tokens.padding.extraSmall
    // Equal shares off this strip's OWN width, never off a segment's
    // laid-out position: a laid-out child's x is only valid after a polish
    // pass, so reading it back would make every highlight's position
    // depend on when its binding happened to run.
    readonly property real segment: root.count > 0 ? (root.width - root.inset * 2) / root.count : 0
    readonly property real segmentHeight: root.height - root.inset * 2

    function offsetOf(i: int): real {
        return root.inset + Math.max(0, i) * root.segment;
    }

    implicitHeight: 36
    radius: Tokens.rounding.full
    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
    clip: true

    // One highlight that glides to whichever segment the pointer is over,
    // rather than each segment flashing its own -- the affordance
    // modules/bar/components/HoverPill.qml gives the bar. Not that
    // component: it is a fixed circle sized off the bar's own thickness,
    // and these are wide segments of a strip.
    StyledRect {
        x: root.offsetOf(root.hoveredIndex)
        y: root.inset
        width: root.segment
        height: root.segmentHeight
        radius: Tokens.rounding.full
        color: Colours.palette.m3onSurface
        visible: opacity > 0
        opacity: root.hoveredIndex >= 0 && root.hoveredIndex !== root.currentIndex ? 0.08 : 0

        Behavior on x {
            Anim { type: Anim.FastEffects }
        }
        Behavior on opacity {
            Anim { type: Anim.FastEffects }
        }
    }

    StyledRect {
        x: root.offsetOf(root.currentIndex)
        y: root.inset
        width: root.segment
        height: root.segmentHeight
        radius: Tokens.rounding.full
        color: Colours.palette.m3primary

        Behavior on x {
            SpringAnimation {
                spring: 4
                damping: 0.62
                mass: 0.9
                epsilon: 0.25
            }
        }
    }

    Repeater {
        model: root.tiles

        Item {
            id: seg

            required property var modelData
            required property int index

            readonly property bool active: seg.index === root.currentIndex
            readonly property bool flagged: root.attentionIds.includes(seg.modelData.id)
            readonly property color fg: seg.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant

            x: root.offsetOf(seg.index)
            y: root.inset
            width: root.segment
            height: root.segmentHeight
            clip: true

            StateLayer {
                radius: seg.height / 2
                disabled: !root.interactive
                // The gliding highlight above is this strip's hover
                // treatment; a second one per segment is the flash it
                // exists to replace. The press ripple still runs.
                stateOpacity: 0
                onClicked: root.picked(seg.modelData.id)
                onContainsMouseChanged: {
                    if (containsMouse)
                        root.hoveredIndex = seg.index;
                    else if (root.hoveredIndex === seg.index)
                        root.hoveredIndex = -1;
                }
            }

            Row {
                id: segRow

                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    id: segIcon

                    anchors.verticalCenter: parent.verticalCenter
                    text: seg.modelData.icon
                    color: seg.fg
                    fontStyle: Tokens.font.icon.small
                    fill: seg.active ? 1 : 0

                    Behavior on color {
                        CAnim {}
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Math.max(0, seg.width - Tokens.padding.small * 2 - segIcon.width - segRow.spacing - (segDot.visible ? segDot.width + segRow.spacing : 0)))
                    elide: Text.ElideRight
                    text: seg.modelData.label
                    color: seg.fg
                    font: Tokens.font.label.builders.medium.weight(seg.active ? Font.Medium : Font.Normal).build()

                    Behavior on color {
                        CAnim {}
                    }
                }

                StyledRect {
                    id: segDot

                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 5
                    implicitHeight: 5
                    radius: Tokens.rounding.full
                    color: seg.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3primary
                    visible: seg.flagged
                }
            }
        }
    }
}
