pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
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
        color: Colours.palette.m3surfaceContainer

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

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: 0.5
            shadowBlur: 0.5
            shadowVerticalOffset: 2
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
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Notifications")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.title.small
                }

                StyledRect {
                    visible: NotificationHistory.unreadCount > 0
                    radius: Tokens.rounding.full
                    color: "transparent"
                    implicitWidth: markAllRow.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: markAllRow.implicitHeight + Tokens.padding.extraSmall * 2

                    RowLayout {
                        id: markAllRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "done_all"
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            text: qsTr("Mark all read")
                            color: Colours.palette.m3primary
                            font: Tokens.font.label.medium
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        onClicked: NotificationHistory.markAllRead()
                    }
                }

                Item {
                    implicitWidth: closeIcon.implicitHeight + Tokens.padding.extraSmall * 2
                    implicitHeight: closeIcon.implicitHeight + Tokens.padding.extraSmall * 2

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
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
                color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

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
