import QtQuick
import qs.config
import qs.services

StyledText {
    property string label: ""
    property bool alive: false

    text: label.toUpperCase()
    color: alive ? Colours.ink : Colours.inkMuted
    font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.6).build()
}
