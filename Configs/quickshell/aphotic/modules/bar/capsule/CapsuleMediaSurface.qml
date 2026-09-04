pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    // False while the capsule is collapsing past this surface -- the
    // seek clock must stop the moment it stops being looked at, not when
    // the item is finally torn down.
    property bool live: false

    readonly property var player: Players.active
    readonly property bool stacked: !Settings.barHorizontal

    function formatTime(seconds: real): string {
        const s = Math.max(0, Math.floor(seconds));
        const m = Math.floor(s / 60);
        const r = s % 60;
        return `${m}:${r < 10 ? "0" : ""}${r}`;
    }

    // MPRIS position is fetched, not pushed -- nothing re-evaluates a
    // `player.position` binding on its own. Re-emitting the notify signal
    // is the only way to tick it, and it runs at 1Hz only while this
    // surface is both open and playing.
    Timer {
        running: root.live && (root.player?.isPlaying ?? false) && (root.player?.positionSupported ?? false) && (root.player?.length ?? 0) > 0
        interval: 1000
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    GridLayout {
        anchors.fill: parent
        flow: root.stacked ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: Tokens.spacing.medium
        rowSpacing: Tokens.spacing.medium

        CapsuleArtwork {
            Layout.alignment: Qt.AlignCenter
            artSize: root.stacked ? 96 : 88
            shaped: Settings.capsuleShapedArt
            source: root.player ? Players.getArtUrl(root.player) : ""
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacing.extraSmall

            Item {
                Layout.fillHeight: true
                visible: !root.stacked
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: root.stacked ? Text.AlignHCenter : Text.AlignLeft
                text: root.player?.trackTitle || qsTr("Nothing playing")
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: root.stacked ? Text.AlignHCenter : Text.AlignLeft
                visible: text.length > 0
                text: root.player?.trackArtist ?? ""
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
                elide: Text.ElideRight
            }

            Item {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.extraSmall
                implicitHeight: 6
                visible: (root.player?.length ?? 0) > 0

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainerHigh
                }

                StyledRect {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primary
                    width: (root.player?.length ?? 0) > 0 ? parent.width * Math.min(1, root.player.position / root.player.length) : 0

                    Behavior on width {
                        enabled: Settings.capsuleAnimations && !seek.pressed
                        Anim { type: Anim.StandardSmall }
                    }
                }

                MouseArea {
                    id: seek

                    anchors.fill: parent
                    anchors.margins: -6
                    enabled: root.player?.canSeek ?? false
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                    function seekToX(x: real): void {
                        if (root.player?.canSeek)
                            root.player.position = Math.min(1, Math.max(0, x / width)) * root.player.length;
                    }

                    onPressed: e => seekToX(e.x)
                    onPositionChanged: e => {
                        if (pressed)
                            seekToX(e.x);
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: (root.player?.length ?? 0) > 0

                StyledText {
                    text: root.formatTime(root.player?.position ?? 0)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    text: root.formatTime(root.player?.length ?? 0)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
            }

            CapsuleTransport {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacing.extraSmall
            }

            Item {
                Layout.fillHeight: true
                visible: !root.stacked
            }
        }
    }
}
