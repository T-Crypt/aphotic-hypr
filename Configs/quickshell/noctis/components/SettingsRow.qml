pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

RowLayout {
    id: root

    required property string icon
    required property string label
    property string description: ""

    default property alias trailing: trailingSlot.data

    Layout.fillWidth: true
    Layout.preferredHeight: root.description.length > 0 ? 56 : 44
    spacing: Tokens.spacing.medium

    StyledRect {
        Layout.preferredWidth: 36
        Layout.preferredHeight: 36
        radius: Tokens.rounding.medium
        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

        MaterialIcon {
            anchors.centerIn: parent
            text: root.icon
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.medium
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            text: root.label
            elide: Text.ElideRight
            font: Tokens.font.body.medium
        }

        StyledText {
            visible: root.description.length > 0
            Layout.fillWidth: true
            text: root.description
            elide: Text.ElideRight
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }

    Item {
        id: trailingSlot

        Layout.preferredWidth: childrenRect.width
        Layout.preferredHeight: childrenRect.height
        Layout.alignment: Qt.AlignVCenter
    }
}
