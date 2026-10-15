pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// The notch's phone tile: the same devices the shelf tab lists, at the
// notch's width, and the same one way to ask the bridge again. Nothing in
// it opens a surface, so unlike the process and palette tiles it needs no
// screenState.
ColumnLayout {
    id: root

    spacing: Tokens.spacing.extraSmall

    Repeater {
        model: Phone.devices

        StyledRect {
            id: row

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: 24
            radius: Tokens.rounding.small
            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.small
                anchors.rightMargin: Tokens.padding.small
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "smartphone"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.small
                    fill: 1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: row.modelData.label
                    elide: Text.ElideRight
                    font: Tokens.font.body.medium
                }
            }
        }
    }

    StyledRect {
        id: refreshRow

        Layout.fillWidth: true
        implicitHeight: 24
        radius: Tokens.rounding.small
        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

        StateLayer {
            radius: parent.radius
            onClicked: Phone.refresh()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.small
            anchors.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "refresh"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Refresh")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }
    }
}
