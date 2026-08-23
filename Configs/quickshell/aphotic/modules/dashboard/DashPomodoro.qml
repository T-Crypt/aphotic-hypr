import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    implicitWidth: 160
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Pomodoro.isBreak ? qsTr("Break") : qsTr("Focus")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Pomodoro.formatTime(Pomodoro.remaining)
            color: Colours.palette.m3secondary
            font: Tokens.font.headline.builders.large.scale(1.3).weight(Font.DemiBold).build()
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.small
            spacing: Tokens.spacing.large

            component PomodoroButton: Item {
                id: btn

                required property string icon
                signal clicked

                implicitWidth: icon_.implicitHeight + Tokens.padding.small * 2
                implicitHeight: implicitWidth

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: btn.clicked()
                }

                MaterialIcon {
                    id: icon_
                    anchors.centerIn: parent
                    text: btn.icon
                    color: Colours.palette.m3onSurface
                    fontStyle: Tokens.font.icon.medium
                }
            }

            PomodoroButton {
                icon: "restart_alt"
                onClicked: Pomodoro.reset()
            }

            PomodoroButton {
                icon: Pomodoro.running ? "pause" : "play_arrow"
                onClicked: Pomodoro.toggle()
            }

            PomodoroButton {
                icon: "skip_next"
                onClicked: Pomodoro.skip()
            }
        }
    }
}
