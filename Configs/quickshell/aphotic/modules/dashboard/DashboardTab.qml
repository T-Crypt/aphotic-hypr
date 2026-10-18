import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    implicitWidth: layout.item?.implicitWidth ?? 0
    implicitHeight: layout.item?.implicitHeight ?? 0

    Loader {
        id: layout

        sourceComponent: bento
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

                SignalCard {
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

                SignalCard {
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

            SignalCard {
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

                SignalCard {
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

                    SignalCard {
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

                    SignalCard {
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

            SignalCard {
                Layout.preferredWidth: dateTimeClassic.implicitWidth
                Layout.preferredHeight: dateTimeClassic.implicitHeight

                DashDateTime {
                    id: dateTimeClassic
                }
            }

            SignalCard {
                Layout.preferredWidth: calendarClassic.implicitWidth
                Layout.preferredHeight: calendarClassic.implicitHeight

                DashCalendar {
                    id: calendarClassic
                }
            }

            SignalCard {
                Layout.preferredWidth: mediaClassic.implicitWidth
                Layout.preferredHeight: mediaClassic.implicitHeight

                DashMedia {
                    id: mediaClassic
                }
            }

            SignalCard {
                Layout.preferredWidth: pomodoroClassic.implicitWidth
                Layout.preferredHeight: pomodoroClassic.implicitHeight

                DashPomodoro {
                    id: pomodoroClassic
                }
            }

            SignalCard {
                Layout.preferredWidth: quickTogglesClassic.implicitWidth
                Layout.preferredHeight: quickTogglesClassic.implicitHeight

                DashQuickToggles {
                    id: quickTogglesClassic
                }
            }

            SignalCard {
                Layout.preferredWidth: weatherClassic.implicitWidth
                Layout.preferredHeight: weatherClassic.implicitHeight

                DashWeather {
                    id: weatherClassic
                }
            }
        }
    }
}
