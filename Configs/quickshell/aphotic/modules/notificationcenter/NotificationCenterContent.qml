pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState

    readonly property bool open: root.screenState.notificationCenter
    readonly property int cardWidth: 400

    implicitWidth: root.cardWidth
    width: root.implicitWidth

    Elevation {
        target: card
        level: Settings.barSignal ? 2 : 3
    }

    StyledRect {
        id: card

        width: root.width
        height: root.height
        // Bound directly to root.open (with the Behaviors below driving
        // the motion) instead of a state/PropertyChanges/Transition
        // block -- matches the Behavior-on-property idiom every other
        // popout in this shell uses (see popouts/Wrapper.qml's
        // flyout/agentFlyout), and shares the exact same Anim.Emphasized
        // curve those use so this overlay opens/closes with the same
        // feel as the rest of the bar.
        x: root.open ? 0 : root.cardWidth
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.96
        transformOrigin: Item.Right
        radius: Tokens.rounding.large
        color: Settings.barSignal ? Colours.signalStyle.glass : Colours.palette.m3surfaceContainer
        border.width: Settings.barSignal ? 1 : 0
        border.color: Colours.signalStyle.hairline

        Behavior on x {
            Anim {
                type: Anim.Emphasized
            }
        }
        Behavior on opacity {
            Anim {
                type: Anim.Emphasized
            }
        }
        Behavior on scale {
            Anim {
                type: Anim.Emphasized
            }
        }

        // No DepthLayer here -- this card's own content (a dense
        // notification list) is already visually busy, per Aphotic
        // Depth's per-surface intensity guidance.
        // The glass tone relies on the compositor blur behind it; the
        // depth gradient only reads on the opaque skins.
        DepthGradient {
            anchors.fill: parent
            visible: !Settings.barSignal
            radius: card.radius
            baseColour: card.color
        }

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "notifications"
                    color: Settings.barSignal ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Notifications")
                    color: Colours.palette.m3onSurface
                    font: Settings.barSignal ? Tokens.font.title.builders.large.weight(Font.DemiBold).build() : Tokens.font.title.small
                }

                StyledRect {
                    visible: NotificationHistory.unreadCount > 0
                    radius: Tokens.rounding.full
                    color: "transparent"
                    border.width: Settings.barSignal ? 1 : 0
                    border.color: Colours.signalStyle.hairline
                    implicitWidth: markAllRow.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: markAllRow.implicitHeight + Tokens.padding.extraSmall * 2

                    RowLayout {
                        id: markAllRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "done_all"
                            color: Colours.palette.m3primary
                            visible: !Settings.barSignal
                            fontStyle: Tokens.font.icon.small
                        }

                        // Signal: the pill reads as the small-caps count label.
                        StyledText {
                            text: Settings.barSignal ? `${NotificationHistory.unreadCount} NEW` : qsTr("Mark all read")
                            color: Settings.barSignal ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary
                            font: Settings.barSignal ? Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build() : Tokens.font.label.medium
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        stateOpacity: Settings.barSignal ? (containsMouse ? 1 : 0) : (containsMouse ? 0.08 : 0)
                        color: Settings.barSignal ? Colours.signalStyle.hover : Colours.palette.m3onSurface
                        onClicked: NotificationHistory.markAllRead()
                    }
                }

                Item {
                    id: clearAll

                    property bool armed: false

                    visible: NotificationHistory.entries.length > 0
                    implicitWidth: clearIcon.implicitHeight + Tokens.padding.extraSmall * 2
                    implicitHeight: clearIcon.implicitHeight + Tokens.padding.extraSmall * 2

                    // The card is 400px, which is why this is an icon and
                    // not the labelled pill "Mark all read" gets. An
                    // unlabelled control that drops the whole history
                    // wants a second press to mean it, so the first one
                    // arms and the icon says so.
                    Timer {
                        id: clearAllDisarm

                        interval: 3000
                        onTriggered: clearAll.armed = false
                    }

                    Connections {
                        target: root

                        function onOpenChanged(): void {
                            if (!root.open) {
                                clearAll.armed = false;
                                clearAllDisarm.stop();
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        border.width: 1
                        border.color: Colours.signalStyle.hairline
                        visible: Settings.barSignal
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        stateOpacity: Settings.barSignal ? (containsMouse ? 1 : 0) : (containsMouse ? 0.08 : 0)
                        color: Settings.barSignal ? Colours.signalStyle.hover : Colours.palette.m3onSurface
                        onClicked: {
                            if (clearAll.armed) {
                                NotificationHistory.clearAll();
                                clearAll.armed = false;
                                clearAllDisarm.stop();
                            } else {
                                clearAll.armed = true;
                                clearAllDisarm.restart();
                            }
                        }
                    }

                    MaterialIcon {
                        id: clearIcon

                        anchors.centerIn: parent
                        text: clearAll.armed ? "delete_forever" : "delete_sweep"
                        color: clearAll.armed ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                        fill: clearAll.armed ? 1 : 0
                        fontStyle: Tokens.font.icon.small
                    }
                }

                Item {
                    implicitWidth: dndIcon.implicitHeight + Tokens.padding.extraSmall * 2
                    implicitHeight: dndIcon.implicitHeight + Tokens.padding.extraSmall * 2

                    Rectangle {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        border.width: 1
                        border.color: Colours.signalStyle.hairline
                        visible: Settings.barSignal
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        stateOpacity: Settings.barSignal ? (containsMouse ? 1 : 0) : (containsMouse ? 0.08 : 0)
                        color: Settings.barSignal ? Colours.signalStyle.hover : Colours.palette.m3onSurface
                        onClicked: DoNotDisturb.toggle()
                    }

                    MaterialIcon {
                        id: dndIcon

                        anchors.centerIn: parent
                        text: DoNotDisturb.enabled ? "notifications_off" : "notifications"
                        color: DoNotDisturb.enabled ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fill: DoNotDisturb.enabled ? 1 : 0
                        fontStyle: Tokens.font.icon.small
                    }
                }

                Item {
                    implicitWidth: closeIcon.implicitHeight + Tokens.padding.extraSmall * 2
                    implicitHeight: closeIcon.implicitHeight + Tokens.padding.extraSmall * 2

                    Rectangle {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        border.width: 1
                        border.color: Colours.signalStyle.hairline
                        visible: Settings.barSignal
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        stateOpacity: Settings.barSignal ? (containsMouse ? 1 : 0) : (containsMouse ? 0.08 : 0)
                        color: Settings.barSignal ? Colours.signalStyle.hover : Colours.palette.m3onSurface
                        onClicked: root.screenState.notificationCenter = false
                    }

                    MaterialIcon {
                        id: closeIcon

                        anchors.centerIn: parent
                        text: "close"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: weatherRow.implicitHeight + Tokens.padding.medium * 2
                visible: Weather.hasData
                radius: Tokens.rounding.medium
                color: Settings.barSignal ? Colours.signalStyle.raised : Colours.layer(Colours.tPalette.m3surfaceContainer, 2)
                border.width: Settings.barSignal ? 1 : 0
                border.color: Colours.signalStyle.hairline

                RowLayout {
                    id: weatherRow

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: Weather.conditionIcon
                        color: Colours.palette.m3secondary
                        fontStyle: Tokens.font.icon.medium
                    }

                    StyledText {
                        text: `${Math.round(Weather.currentTemp)}°${Settings.weatherUnits === "fahrenheit" ? "F" : "C"}`
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.medium
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Weather.conditionText
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }
                }
            }

            ListView {
                id: list

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Tokens.spacing.small

                model: ScriptModel {
                    values: NotificationHistory.entries
                }

                delegate: NotificationHistoryItem {
                    width: list.width
                }

                // New entries fade+rise in and existing ones glide to
                // their new slot on the same Emphasized curve as the
                // card itself, rather than snapping to position.
                add: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Tokens.anim.durations.expressiveDefaultEffects
                        easing: Tokens.anim.emphasizedDecel
                    }
                }

                displaced: Transition {
                    Anim {
                        type: Anim.Emphasized
                        properties: "x,y"
                    }
                }

                // Removed rows fade while sliding out toward the screen
                // edge the card is docked to.
                remove: Transition {
                    Anim {
                        type: Anim.FastEffects
                        property: "x"
                        to: Tokens.spacing.largeIncreased
                    }
                    Anim {
                        type: Anim.FastEffects
                        property: "opacity"
                        to: 0
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "notifications_none"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("No notifications yet")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.medium
                    }
                }
            }
        }
    }
}
