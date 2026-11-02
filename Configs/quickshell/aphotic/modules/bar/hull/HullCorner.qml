pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.config
import qs.services

// One corner of the hull frame: a pointer hot zone, the state node drawn in
// it, and the flyout card that grows out of it. Corners are 0 top-left,
// 1 top-right, 2 bottom-left, 3 bottom-right, the same order ConcaveCorner
// uses.
Item {
    id: root

    required property int corner
    required property real zoneWidth
    required property real zoneHeight

    property string level: "idle"
    property string title
    property string detail
    property var actions: []

    readonly property bool atRight: root.corner === 1 || root.corner === 3
    readonly property bool atBottom: root.corner >= 2
    readonly property bool open: root._open && root.enabled
    readonly property alias zoneItem: zone
    readonly property alias cardItem: card

    property bool _open: false

    function close(): void {
        root._open = false;
    }

    anchors.fill: parent

    onEnabledChanged: {
        if (!root.enabled)
            root._open = false;
    }

    Item {
        id: zone

        x: root.atRight ? root.width - width : 0
        y: root.atBottom ? root.height - height : 0
        width: root.zoneWidth
        height: root.zoneHeight

        HoverHandler {
            id: zoneHover

            onHoveredChanged: {
                if (zoneHover.hovered) {
                    leave.stop();
                    if (!root._open)
                        dwell.restart();
                } else {
                    dwell.stop();
                    leave.restart();
                }
            }
        }

        TapHandler {
            onTapped: {
                dwell.stop();
                root._open = !root._open;
            }
        }

        Rectangle {
            id: node

            readonly property color tint: root.level === "warn" ? Colours.status.warning : root.level === "active" ? Colours.signalStyle.accentLine : Colours.signalStyle.hairline

            anchors.centerIn: parent
            implicitWidth: root.level === "idle" ? 5 : 7
            implicitHeight: implicitWidth
            radius: width / 2
            color: node.tint
            opacity: root.open || zoneHover.hovered ? 1 : root.level === "idle" ? 0.55 : 0.9

            Behavior on implicitWidth {
                Anim {
                    type: Anim.FastSpatial
                }
            }
            Behavior on color {
                CAnim {}
            }
            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }

            Rectangle {
                id: ping

                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: node.tint
                opacity: 0
            }

            ParallelAnimation {
                id: pingAnim

                NumberAnimation {
                    target: ping
                    property: "scale"
                    from: 1
                    to: 3.2
                    duration: Tokens.anim.durations.expressiveDefaultSpatial
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: ping
                    property: "opacity"
                    from: 0.7
                    to: 0
                    duration: Tokens.anim.durations.expressiveDefaultSpatial
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    onLevelChanged: {
        if (root.level !== "idle" && RenderGate.decorative)
            pingAnim.restart();
    }

    Timer {
        id: dwell

        interval: Config.hull.cornerDwell
        onTriggered: root._open = true
    }

    Timer {
        id: leave

        interval: 260
        onTriggered: {
            if (!zoneHover.hovered && !cardHover.hovered)
                root._open = false;
        }
    }

    SignalSurface {
        id: card

        readonly property real pad: Tokens.padding.large

        // Flush against the zone on its inward side: a gap between the two
        // is a dead strip the pointer crosses with no hover, which would
        // close the card on the way to it.
        x: root.atRight ? root.width - width : 0
        y: root.atBottom ? root.height - root.zoneHeight - height : root.zoneHeight
        width: 264
        height: column.implicitHeight + card.pad * 2
        radius: Tokens.rounding.large
        tone: Colours.signalStyle.raised
        openEdge: root.atBottom ? "end" : "start"

        visible: opacity > 0
        opacity: root.open ? 1 : 0
        enabled: root.open

        transform: Scale {
            origin.x: root.atRight ? card.width : 0
            origin.y: root.atBottom ? card.height : 0
            xScale: root.open ? 1 : 0.86
            yScale: root.open ? 1 : 0.86

            Behavior on xScale {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
            Behavior on yScale {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        HoverHandler {
            id: cardHover

            onHoveredChanged: {
                if (cardHover.hovered)
                    leave.stop();
                else
                    leave.restart();
            }
        }

        Column {
            id: column

            x: card.pad
            y: card.pad
            width: card.width - card.pad * 2
            spacing: Tokens.spacing.small

            Row {
                spacing: Tokens.spacing.small

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6
                    height: 6
                    radius: width / 2
                    color: node.tint
                }

                StyledText {
                    text: root.title
                    font: Tokens.font.label.medium
                    color: Colours.ink
                }
            }

            StyledText {
                width: column.width
                visible: text.length > 0
                text: root.detail
                wrapMode: Text.WordWrap
                font: Tokens.font.label.small
                color: Colours.inkMuted
            }

            Rectangle {
                width: column.width
                height: 1
                color: Colours.signalStyle.hairline
                opacity: 0.6
            }

            Repeater {
                model: root.actions

                StyledRect {
                    id: action

                    required property var modelData

                    width: column.width
                    implicitHeight: 34
                    radius: Tokens.rounding.medium
                    color: "transparent"

                    Interact {
                        radius: action.radius
                        onClicked: {
                            action.modelData.run();
                            root._open = false;
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Tokens.padding.medium
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: action.modelData.icon
                            color: action.modelData.on ? Colours.signalStyle.accentLine : Colours.ink
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: action.modelData.label
                            font: Tokens.font.label.medium
                            color: Colours.ink
                        }
                    }
                }
            }
        }
    }
}
