pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// The devices the bridge has in reach, and one way to ask it again. The
// host only mounts this tab while at least one device is there, so there is
// no empty state to draw: an empty list is exactly what unmounts it.
Flickable {
    id: root

    contentWidth: width
    contentHeight: layout.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    ColumnLayout {
        id: layout

        width: root.width
        spacing: Tokens.spacing.extraSmall

        Repeater {
            model: Phone.devices

            delegate: Item {
                id: row

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: Tokens.sizes.bar.innerWidth

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.full
                    color: Colours.layer(Colours.raised, 2)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        Layout.preferredWidth: Tokens.sizes.bar.innerWidth * 0.6
                        text: "smartphone"
                        fontStyle: Tokens.font.icon.medium
                        fill: 1
                        color: Colours.signal
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.label
                        elide: Text.ElideRight
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        Item {
            id: refreshRow

            Layout.fillWidth: true
            implicitHeight: Tokens.sizes.bar.innerWidth

            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.full
                color: Colours.layer(Colours.raised, 2)
            }

            Interact {
                radius: Tokens.rounding.full
                onClicked: Phone.refresh()
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.preferredWidth: Tokens.sizes.bar.innerWidth * 0.6
                    text: "refresh"
                    fontStyle: Tokens.font.icon.medium
                    color: Colours.inkMuted
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Refresh")
                    color: Colours.inkMuted
                    font: Tokens.font.label.small
                }
            }
        }
    }
}
