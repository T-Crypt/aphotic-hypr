import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    spacing: Tokens.spacing.small

    RowLayout {
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "keyboard_capslock"
            color: Hypr.capsLock ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
        }
        StyledText {
            text: qsTr("Caps Lock: %1").arg(Hypr.capsLock ? qsTr("on") : qsTr("off"))
        }
    }

    RowLayout {
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "dialpad"
            color: Hypr.numLock ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
        }
        StyledText {
            text: qsTr("Num Lock: %1").arg(Hypr.numLock ? qsTr("on") : qsTr("off"))
        }
    }
}
