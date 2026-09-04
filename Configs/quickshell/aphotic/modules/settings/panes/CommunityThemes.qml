pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.modules.settings

// The "available to download" half of Settings -> Appearance, on its own
// page so the landing pane keeps one row for it however long the
// catalogue gets. Owns no state: the pane holds the fetch (so the
// downloaded-theme badge and this list agree) and runs the download.
ColumnLayout {
    id: root

    required property var available

    signal back
    signal download(string name)

    spacing: Tokens.spacing.medium

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        StyledRect {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: Tokens.rounding.full
            color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

            MaterialIcon {
                anchors.centerIn: parent
                text: "arrow_back"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.back()
            }
        }

        StyledText {
            text: qsTr("Community themes")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
        }
    }

    StyledText {
        visible: root.available.length === 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Nothing to download. Either every published theme is already installed, or the aphotic-themes index couldn't be reached.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.available.length > 0
        contentWidth: width
        contentHeight: cards.implicitHeight
        clip: true

        Flow {
            id: cards

            width: parent.width
            spacing: Tokens.spacing.medium

            Repeater {
                model: root.available

                StyledRect {
                    id: communityCard

                    required property var modelData

                    width: 220
                    implicitHeight: communityCol.implicitHeight + Tokens.padding.large * 2
                    radius: Tokens.rounding.medium
                    color: Colours.tPalette.m3surfaceContainer

                    ColumnLayout {
                        id: communityCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.padding.large
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: communityCard.modelData.display_name
                            font: Tokens.font.body.medium
                        }

                        StyledText {
                            visible: (communityCard.modelData.description ?? "").length > 0
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: communityCard.modelData.description ?? ""
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }

                        StyledText {
                            Layout.topMargin: Tokens.spacing.extraSmall
                            text: qsTr("%1 wallpapers · %2").arg(communityCard.modelData.wallpaper_count ?? 0).arg(ModelStorage.formatBytes(communityCard.modelData.approx_size_bytes ?? 0))
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }

                        StyledRect {
                            Layout.topMargin: Tokens.spacing.small
                            Layout.alignment: Qt.AlignLeft
                            implicitWidth: downloadLabel.implicitWidth + Tokens.padding.large * 2
                            implicitHeight: 28
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3primary

                            StyledText {
                                id: downloadLabel
                                anchors.centerIn: parent
                                text: qsTr("Download")
                                color: Colours.contrastOn(Colours.palette.m3primary)
                                font: Tokens.font.label.small
                            }

                            StateLayer {
                                anchors.fill: parent
                                radius: parent.radius
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.download(communityCard.modelData.name)
                            }
                        }
                    }
                }
            }
        }
    }
}
