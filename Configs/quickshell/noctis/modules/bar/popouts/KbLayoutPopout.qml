import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    spacing: Tokens.spacing.small / 2

    StyledText {
        text: qsTr("Keyboard layout")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    StyledText {
        text: Hypr.kbLayout || qsTr("Unknown")
        font: Tokens.font.title.medium
    }
}
