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

        // Seek bar
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            visible: Players.active?.length > 0

            StyledRect {
                anchors.fill: parent
                radius: height / 2
                color: Colours.tPalette.m3surfaceContainer
            }

            StyledRect {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: parent.height / 2
                width: Players.active?.length > 0 ? parent.width * Math.min(1, Players.active.position / Players.active.length) : 0
                color: Colours.palette.m3primary

                Behavior on width {
                    enabled: !dashSeekArea.pressed
                    Anim {}
                }
            }

            MouseArea {
                id: dashSeekArea

                anchors.fill: parent
                enabled: Players.active?.canSeek ?? false
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                function seekToX(x: real): void {
                    if (Players.active?.canSeek)
                        Players.active.position = Math.min(1, Math.max(0, x / width)) * Players.active.length;
                }

                onPressed: mouse => seekToX(mouse.x)
                onPositionChanged: mouse => {
                    if (pressed)
                        seekToX(mouse.x);
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: Players.active?.length > 0

            StyledText {
                text: root.formatTime(Players.active?.position ?? 0)
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                text: root.formatTime(Players.active?.length ?? 0)
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }
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

        // Player switcher -- only shown when more than one MPRIS source is
        // active (e.g. Spotify + a browser tab).
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small
            visible: Players.list.length > 1

            Repeater {
                model: Players.list

                Item {
                    id: dot

                    required property var modelData

                    implicitWidth: 8
                    implicitHeight: 8

                    StateLayer {
                        anchors.fill: parent
                        radius: 4
                        color: dot.modelData === Players.active ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
                        onClicked: Players.manualActive = dot.modelData
                    }
                }
            }
        }
    }

    function formatTime(seconds: real): string {
        const s = Math.max(0, Math.floor(seconds));
        const m = Math.floor(s / 60);
        const r = s % 60;
        return `${m}:${r < 10 ? "0" : ""}${r}`;
    }
}
