pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    // False the moment the capsule starts collapsing past this, not when
    // the item is finally torn down: the seek clock has to stop when it
    // stops being looked at.
    property bool live: false
    property bool stacked: false

    readonly property var player: Players.active
    readonly property int artSize: root.stacked ? 108 : 96

    function formatTime(seconds: real): string {
        const s = Math.max(0, Math.floor(seconds));
        const m = Math.floor(s / 60);
        const r = s % 60;
        return `${m}:${r < 10 ? "0" : ""}${r}`;
    }

    // MPRIS position is fetched, not pushed: nothing re-evaluates a
    // `player.position` binding on its own, and re-emitting the notify
    // signal is the only way to tick it. Runs at 1Hz, and only while this
    // area is both open and playing.
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
        rowSpacing: Tokens.spacing.small

        CapsuleArtwork {
            Layout.alignment: Qt.AlignCenter
            Layout.preferredWidth: root.artSize
            Layout.preferredHeight: root.artSize
            artSize: root.artSize
            shaped: Settings.capsuleShapedArt
            source: root.player ? Players.getArtUrl(root.player) : ""
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.extraSmall

            Item {
                Layout.fillHeight: true
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

            // Elapsed, track, remaining on ONE row. Stacking the times under
            // the bar costs a whole extra line of height, which is the
            // difference between the media area fitting and being clipped.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.extraSmall
                spacing: Tokens.spacing.small
                visible: (root.player?.length ?? 0) > 0

                StyledText {
                    text: root.formatTime(root.player?.position ?? 0)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 6

                    StyledRect {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 5
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHigh
                    }

                    StyledRect {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        height: 5
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary
                        width: (root.player?.length ?? 0) > 0 ? parent.width * Math.min(1, root.player.position / root.player.length) : 0

                        Behavior on width {
                            enabled: Settings.capsuleAnimations && !seek.pressed
                            Anim {
                                type: Anim.StandardSmall
                            }
                        }
                    }

                    MouseArea {
                        id: seek

                        anchors.fill: parent
                        anchors.topMargin: -6
                        anchors.bottomMargin: -6
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

                StyledText {
                    text: root.formatTime(root.player?.length ?? 0)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
            }

            CapsuleTransport {
                Layout.alignment: root.stacked ? Qt.AlignHCenter : Qt.AlignLeft
                Layout.topMargin: Tokens.spacing.extraSmall
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }
}
