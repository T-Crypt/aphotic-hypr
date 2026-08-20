import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property var player: Players.active

    spacing: Tokens.spacing.medium

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
            radius: Tokens.rounding.medium
            color: Colours.palette.m3surfaceContainerHigh
            clip: true

            Image {
                anchors.fill: parent
                source: root.player ? Players.getArtUrl(root.player) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: source.toString().length > 0
            }

            MaterialIcon {
                anchors.centerIn: parent
                visible: !root.player || Players.getArtUrl(root.player).length === 0
                text: "music_note"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.large
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small / 2

            StyledText {
                Layout.maximumWidth: 220
                text: root.player?.trackTitle || qsTr("No media playing")
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                Layout.maximumWidth: 220
                visible: text.length > 0
                text: root.player?.trackArtist ?? ""
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
                elide: Text.ElideRight
            }

            StyledText {
                Layout.maximumWidth: 220
                visible: text.length > 0
                text: Players.getIdentity(root.player)
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }
    }

    // Seek bar -- draggable when the active player supports it, otherwise a
    // plain read-only progress fill.
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 6
        visible: root.player?.length > 0

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
            width: root.player?.length > 0 ? parent.width * Math.min(1, root.player.position / root.player.length) : 0
            color: Colours.palette.m3tertiary

            Behavior on width {
                enabled: !seekArea.pressed
                Anim {}
            }
        }

        MouseArea {
            id: seekArea

            anchors.fill: parent
            enabled: root.player?.canSeek ?? false
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

            function seekToX(x: real): void {
                if (root.player?.canSeek)
                    root.player.position = Math.min(1, Math.max(0, x / width)) * root.player.length;
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
        visible: root.player?.length > 0

        StyledText {
            text: root.formatTime(root.player?.position ?? 0)
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }

        Item {
            Layout.fillWidth: true
        }

        StyledText {
            text: root.formatTime(root.player?.length ?? 0)
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
            enabled_: root.player?.canGoPrevious ?? false
            onClicked: root.player?.previous()
        }

        MediaButton {
            icon: root.player?.isPlaying ? "pause" : "play_arrow"
            enabled_: root.player?.canTogglePlaying ?? false
            onClicked: root.player?.togglePlaying()
        }

        MediaButton {
            icon: "skip_next"
            enabled_: root.player?.canGoNext ?? false
            onClicked: root.player?.next()
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
                    color: dot.modelData === root.player ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
                    onClicked: Players.manualActive = dot.modelData
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
