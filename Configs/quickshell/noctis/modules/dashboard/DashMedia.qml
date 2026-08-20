import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    implicitWidth: 220
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        width: parent.width - Tokens.padding.large * 2
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 140
            Layout.preferredHeight: 140
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainerHigh
            clip: true

            Image {
                anchors.fill: parent
                source: Players.active ? Players.getArtUrl(Players.active) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: source.toString().length > 0
            }

            MaterialIcon {
                anchors.centerIn: parent
                visible: !Players.active || Players.getArtUrl(Players.active).length === 0
                text: "music_note"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.extraLarge
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            text: Players.active?.trackTitle || qsTr("No media playing")
            color: Colours.palette.m3onSurface
            font: Tokens.font.body.medium
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            visible: text.length > 0
            text: Players.active?.trackArtist ?? ""
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.large

            component MediaButton: Item {
                id: btn

                required property string icon
                required property bool enabled_
                signal clicked

                implicitWidth: icon_.implicitHeight + Tokens.padding.small * 2
                implicitHeight: implicitWidth
                opacity: enabled_ ? 1 : 0.4

                StateLayer {
                    radius: Tokens.rounding.full
                    disabled: !btn.enabled_
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

            MediaButton {
                icon: "skip_previous"
                enabled_: Players.active?.canGoPrevious ?? false
                onClicked: Players.active?.previous()
            }

            MediaButton {
                icon: Players.active?.isPlaying ? "pause" : "play_arrow"
                enabled_: Players.active?.canTogglePlaying ?? false
                onClicked: Players.active?.togglePlaying()
            }

            MediaButton {
                icon: "skip_next"
                enabled_: Players.active?.canGoNext ?? false
                onClicked: Players.active?.next()
            }
        }
    }
}
