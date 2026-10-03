pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// What is playing right now, with transport. Reads the one player list the
// shell already runs -- opening this tab starts no watcher of its own.
Flickable {
    id: root

    contentWidth: width
    contentHeight: layout.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    readonly property var player: Players.active

    ColumnLayout {
        id: layout

        width: root.width
        spacing: Tokens.spacing.small

        StyledText {
            Layout.fillWidth: true
            Layout.margins: Tokens.padding.small
            text: root.player?.title ?? qsTr("Nothing playing")
            color: Colours.palette.m3onSurface
            font: Tokens.font.label.medium
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.WordWrap
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            Layout.rightMargin: Tokens.padding.small
            text: root.player?.artist ?? ""
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Tokens.padding.small
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: [
                    { icon: "skip_previous", enabled: root.player?.canGoPrevious ?? false, action: () => root.player?.previous() },
                    { icon: root.player?.isPlaying ? "pause" : "play_arrow", enabled: root.player !== null, action: () => root.player?.togglePlaying() },
                    { icon: "skip_next", enabled: root.player?.canGoNext ?? false, action: () => root.player?.next() }
                ]

                delegate: Item {
                    id: button

                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: Settings.barInnerWidth
                    opacity: button.modelData.enabled ? 1 : 0.4

                    StyledRect {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                    }

                    StateLayer {
                        radius: Tokens.rounding.full
                        enabled: button.modelData.enabled
                        onClicked: button.modelData.action()
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: button.modelData.icon
                        fontStyle: Tokens.font.icon.medium
                        color: Colours.palette.m3onSurface
                    }
                }
            }
        }
    }
}