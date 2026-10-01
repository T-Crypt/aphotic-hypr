import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    KeyboardStateWatch {}

    spacing: Tokens.spacing.small / 2

    StyledText {
        text: Settings.barSignal ? qsTr("Keyboard layout").toUpperCase() : qsTr("Keyboard layout")
        color: Colours.palette.m3onSurfaceVariant
        font: Settings.barSignal ? Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build() : Tokens.font.label.medium
    }

    StyledText {
        text: Hypr.kbLayout || qsTr("Unknown")
        font: Settings.barSignal ? Tokens.font.title.builders.medium.weight(Font.DemiBold).build() : Tokens.font.title.medium
    }
}
