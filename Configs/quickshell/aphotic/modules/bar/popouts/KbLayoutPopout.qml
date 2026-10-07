import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    KeyboardStateWatch {}

    spacing: Tokens.spacing.small / 2

    StyledText {
        text: qsTr("Keyboard layout").toUpperCase()
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
    }

    StyledText {
        text: Hypr.kbLayout || qsTr("Unknown")
        font: Tokens.font.title.builders.medium.weight(Font.DemiBold).build()
    }
}
