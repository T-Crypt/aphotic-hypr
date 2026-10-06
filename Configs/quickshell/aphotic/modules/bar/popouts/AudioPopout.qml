import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.utils
import qs.modules.osd

ColumnLayout {
    id: root

    spacing: Tokens.spacing.medium

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: Icons.getVolumeIcon(Audio.volume, Audio.muted)
            color: Colours.palette.m3onSurface

            MouseArea {
                anchors.fill: parent
                anchors.margins: -Tokens.padding.small
                cursorShape: Qt.PointingHandCursor
                onClicked: Audio.setVolume(Audio.muted ? Audio.volume : 0)
            }
        }

        OsdSlider {
            Layout.fillWidth: true
            icon: Icons.getVolumeIcon(Audio.volume, Audio.muted)
            value: Audio.muted ? 0 : Audio.volume
            to: GlobalConfig.services.maxVolume
            onMoved: v => Audio.setVolume(v)
            onWheelUp: Audio.incrementVolume()
            onWheelDown: Audio.decrementVolume()
        }
    }

    StyledText {
        text: qsTr("Output").toUpperCase()
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
    }

    Repeater {
        model: Audio.sinks

        Item {
            id: sinkRow

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: sinkLabel.implicitHeight + Tokens.padding.small * 2

            StateLayer {
                radius: Tokens.rounding.medium
                color: (sinkRow.modelData === Audio.sink ? Colours.palette.m3primary : Colours.signalStyle.hover)
                stateOpacity: (sinkRow.modelData === Audio.sink ? (containsMouse ? 0.22 : 0.14) : (containsMouse ? 1 : 0))
                onClicked: Audio.setAudioSink(sinkRow.modelData)
            }

            Rectangle {
                visible: sinkRow.modelData === Audio.sink
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: parent.height - Tokens.padding.small * 2
                radius: Tokens.rounding.full
                color: Colours.signalStyle.accentLine
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: sinkRow.modelData === Audio.sink ? "radio_button_checked" : "radio_button_unchecked"
                    color: sinkRow.modelData === Audio.sink ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    id: sinkLabel
                    Layout.fillWidth: true
                    text: sinkRow.modelData.description || sinkRow.modelData.name
                    elide: Text.ElideRight
                }
            }
        }
    }
}
