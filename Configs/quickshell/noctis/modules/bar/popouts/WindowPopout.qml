import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    spacing: Tokens.spacing.small / 2

    StyledText {
        Layout.maximumWidth: 320
        text: Hypr.activeToplevel?.title || qsTr("Desktop")
        font: Tokens.font.body.medium
        wrapMode: Text.Wrap
    }

    StyledText {
        visible: !!Hypr.activeToplevel?.lastIpcObject.class
        Layout.maximumWidth: 320
        text: Hypr.activeToplevel?.lastIpcObject.class ?? ""
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
        elide: Text.ElideRight
    }
}
