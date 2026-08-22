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
        text: qsTr("Output")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    Repeater {
        model: Audio.sinks

        Item {
            id: sinkRow

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: sinkLabel.implicitHeight + Tokens.padding.small * 2

            StateLayer {
                radius: Tokens.rounding.small
                onClicked: Audio.setAudioSink(sinkRow.modelData)
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
