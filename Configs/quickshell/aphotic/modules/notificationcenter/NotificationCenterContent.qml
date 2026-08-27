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

    state: root.open ? "open" : ""

    states: State {
        name: "open"
        PropertyChanges {
            card.x: 0
            card.opacity: 1
            card.scale: 1
        }
    }

    transitions: [
        Transition {
            from: ""
            to: "open"
            NumberAnimation {
                properties: "x,opacity,scale"
                duration: Tokens.anim.durations.small
                easing: Tokens.anim.emphasizedDecel
            }
        },
        Transition {
            from: "open"
            to: ""
            NumberAnimation {
                properties: "x,opacity,scale"
                duration: Tokens.anim.durations.expressiveFastEffects
                easing: Tokens.anim.emphasizedAccel
            }
        }
    ]

    StyledRect {
        id: card

        width: root.width
        height: root.height
        x: root.cardWidth
        opacity: 0
        scale: 0.96
        transformOrigin: Item.Right

        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer

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

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Notifications")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.title.small
                }

                StyledText {
                    visible: NotificationHistory.unreadCount > 0
                    text: qsTr("Mark all read")
                    color: Colours.palette.m3primary
                    font: Tokens.font.label.medium

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Tokens.padding.small
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotificationHistory.markAllRead()
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

                StyledText {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: qsTr("No notifications yet")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }
            }
        }
    }
}
