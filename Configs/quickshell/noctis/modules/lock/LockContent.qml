pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property var lock
    required property var pam

    implicitWidth: 380
    implicitHeight: layout.implicitHeight + Tokens.padding.extraLarge * 2

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        width: parent.width - Tokens.padding.extraLarge * 2
        spacing: Tokens.spacing.large

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Time.format("hh:mm")
            font: Tokens.font.headline.builders.large.scale(2).build()
            color: Colours.palette.m3onSurface
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Time.format("dddd, MMMM d")
            font: Tokens.font.body.large
            color: Colours.palette.m3onSurfaceVariant
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            Layout.topMargin: Tokens.spacing.large

            StyledRect {
                id: field

                anchors.fill: parent
                radius: Tokens.rounding.full
                color: Colours.tPalette.m3surfaceContainer

                focus: true
                onActiveFocusChanged: {
                    if (!activeFocus)
                        forceActiveFocus();
                }

                Keys.onPressed: event => root.pam.handleKey(event)

                MaterialIcon {
                    id: icon

                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.padding.large
                    anchors.verticalCenter: parent.verticalCenter

                    text: root.pam.state === Pam.MaxTries ? "lock_clock" : root.pam.state !== Pam.None ? "error" : "lock"
                    color: root.pam.state !== Pam.None ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }

                Row {
                    anchors.left: icon.right
                    anchors.leftMargin: Tokens.spacing.medium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: root.pam.buffer.length

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: Colours.palette.m3onSurface
                        }
                    }

                    StyledText {
                        text: root.pam.buffer.length === 0 ? qsTr("Enter password…") : ""
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.medium
                    }
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: text.length > 0
            text: {
                if (root.pam.state === Pam.MaxTries)
                    return qsTr("Too many attempts — locked out temporarily");
                if (root.pam.state === Pam.Error)
                    return qsTr("Authentication error");
                if (root.pam.state === Pam.Failed)
                    return qsTr("Incorrect password");
                return "";
            }
            color: Colours.palette.m3error
            font: Tokens.font.body.small
        }
    }
}
