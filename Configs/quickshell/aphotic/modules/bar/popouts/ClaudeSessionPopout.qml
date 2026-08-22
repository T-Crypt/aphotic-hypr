import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    spacing: Tokens.spacing.small / 2

    StyledText {
        text: qsTr("Claude Code")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    StyledText {
        text: ClaudeSessions.count > 0 ? qsTr("%1 session(s) running").arg(ClaudeSessions.count) : qsTr("No sessions running")
        font: Tokens.font.title.medium
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        visible: ClaudeSessions.count > 0
        text: qsTr("Click the bar icon to focus the nearest terminal")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }
}
