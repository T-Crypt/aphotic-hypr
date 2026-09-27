import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    implicitWidth: layout.item?.implicitWidth ?? 0
    implicitHeight: layout.item?.implicitHeight ?? 0

    component Card: StyledRect {
        id: card

        property string title: ""
        property int tintIndex: 0
        readonly property real headerHeight: card.title.length > 0 && Settings.barSignal ? cardTitle.implicitHeight + Tokens.padding.medium : 0

        radius: Settings.barSignal ? Tokens.rounding.medium : Tokens.rounding.extraLarge
        color: Settings.barSignal ? Colours.signalStyle.raised : Colours.tPalette.m3surfaceContainer
        border.width: Settings.barSignal ? 1 : 0
        border.color: Colours.signalStyle.hairline

        Elevation {
            visible: Settings.barSignal
            target: card
            level: 1
        }

        Rectangle {
            visible: Settings.barSignal
            x: card.radius
            width: card.width - card.radius * 2
            height: 1
            color: Colours.signalStyle.edgeLight
        }

        Row {
            id: cardTitle

            visible: card.headerHeight > 0
            x: Tokens.padding.large
            y: Tokens.padding.medium
            spacing: Tokens.spacing.small

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: Colours.signalStyle.tint(card.tintIndex)
            }

            StyledText {
                text: card.title.toUpperCase()
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
            }
        }
    }

    Loader {
        id: layout

        sourceComponent: Settings.barSignal ? bento : row
    }

    // Signal: grouped bento. Today over Weather, Calendar, then Now playing
    // over Timer and Controls, every column sharing one height.
    Component {
        id: bento

        RowLayout {
            spacing: Tokens.spacing.medium

            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: Math.max(dateTime.implicitWidth, weather.implicitWidth) + Tokens.padding.large * 2
                spacing: Tokens.spacing.medium

                Card {
                    id: todayCard

                    title: qsTr("Today")
                    tintIndex: 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: todayCard.headerHeight + dateTime.implicitHeight

                    DashDateTime {
                        id: dateTime

                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: todayCard.headerHeight / 2
                    }
                }

                Card {
                    id: weatherCard

                    title: qsTr("Weather")
                    tintIndex: 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: weatherCard.headerHeight + weather.implicitHeight

                    DashWeather {
                        id: weather

                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: weatherCard.headerHeight / 2
                    }
                }
            }

            Card {
                id: calendarCard

                title: qsTr("Calendar")
                tintIndex: 2
                Layout.fillHeight: true
                Layout.preferredWidth: calendar.implicitWidth
                Layout.preferredHeight: calendarCard.headerHeight + calendar.implicitHeight

                DashCalendar {
                    id: calendar

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: calendarCard.headerHeight
                }
            }

            ColumnLayout {
                Layout.fillHeight: true
                spacing: Tokens.spacing.medium

                Card {
                    id: mediaCard

                    title: qsTr("Now playing")
                    tintIndex: 3
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: mediaCard.headerHeight + media.implicitHeight

                    DashMedia {
                        id: media

                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: mediaCard.headerHeight
                    }
                }

                RowLayout {
                    spacing: Tokens.spacing.medium

                    Card {
                        id: focusCard

                        title: qsTr("Timer")
                        tintIndex: 1
                        Layout.fillHeight: true
                        Layout.preferredWidth: pomodoro.implicitWidth
                        Layout.preferredHeight: focusCard.headerHeight + pomodoro.implicitHeight

                        DashPomodoro {
                            id: pomodoro

                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: focusCard.headerHeight
                        }
                    }

                    Card {
                        id: controlsCard

                        title: qsTr("Controls")
                        tintIndex: 0
                        Layout.fillHeight: true
                        Layout.preferredWidth: quickToggles.implicitWidth
                        Layout.preferredHeight: controlsCard.headerHeight + quickToggles.implicitHeight

                        DashQuickToggles {
                            id: quickToggles

                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: controlsCard.headerHeight / 2
                        }
                    }
                }
            }
        }
    }

    Component {
        id: row

        RowLayout {
            spacing: Tokens.spacing.medium

            Card {
                Layout.preferredWidth: dateTimeClassic.implicitWidth
                Layout.preferredHeight: dateTimeClassic.implicitHeight

                DashDateTime {
                    id: dateTimeClassic
                }
            }

            Card {
                Layout.preferredWidth: calendarClassic.implicitWidth
                Layout.preferredHeight: calendarClassic.implicitHeight

                DashCalendar {
                    id: calendarClassic
                }
            }

            Card {
                Layout.preferredWidth: mediaClassic.implicitWidth
                Layout.preferredHeight: mediaClassic.implicitHeight

                DashMedia {
                    id: mediaClassic
                }
            }

            Card {
                Layout.preferredWidth: pomodoroClassic.implicitWidth
                Layout.preferredHeight: pomodoroClassic.implicitHeight

                DashPomodoro {
                    id: pomodoroClassic
                }
            }

            Card {
                Layout.preferredWidth: quickTogglesClassic.implicitWidth
                Layout.preferredHeight: quickTogglesClassic.implicitHeight

                DashQuickToggles {
                    id: quickTogglesClassic
                }
            }

            Card {
                Layout.preferredWidth: weatherClassic.implicitWidth
                Layout.preferredHeight: weatherClassic.implicitHeight

                DashWeather {
                    id: weatherClassic
                }
            }
        }
    }
}
