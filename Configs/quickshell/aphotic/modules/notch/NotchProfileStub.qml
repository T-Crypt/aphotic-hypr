import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// Stands in for an opt-in layer that is installed and docked in the notch
// but whose surface has not been built yet. It says exactly that rather
// than inventing a status, because an empty-but-honest tab is the point:
// the gating and the switcher are real now, the content lands per layer.
ColumnLayout {
    id: root

    required property string slotLabel
    required property string slotIcon

    spacing: Tokens.spacing.small

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Tokens.spacing.medium
    }

    MaterialIcon {
        Layout.alignment: Qt.AlignHCenter
        text: root.slotIcon
        color: Colours.palette.m3onSurfaceVariant
        fontStyle: Tokens.font.icon.extraLarge
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        text: root.slotLabel
        font: Tokens.font.title.medium
    }

    StyledText {
        Layout.fillWidth: true
        text: qsTr("This layer is installed and docked here. Its surface hasn't been built yet.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Tokens.spacing.medium
    }
}
