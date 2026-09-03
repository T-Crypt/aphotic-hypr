import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// Deliberately empty second tile. It exists to prove the tile switcher in
// Notch.qml carries more than one tile (state, header, chip strip and the
// height animation between differently-sized bodies) -- Dev Status and
// Claude Status content are explicitly out of scope for this pass.
ColumnLayout {
    id: root

    spacing: Tokens.spacing.small

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Tokens.spacing.medium
    }

    MaterialIcon {
        Layout.alignment: Qt.AlignHCenter
        text: "extension"
        color: Colours.palette.m3onSurfaceVariant
        fontStyle: Tokens.font.icon.extraLarge
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        text: qsTr("Tile slot reserved")
        font: Tokens.font.title.medium
    }

    StyledText {
        Layout.fillWidth: true
        text: qsTr("Nothing is wired here yet — this slot only exists to prove the switcher holds more than one tile.")
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
