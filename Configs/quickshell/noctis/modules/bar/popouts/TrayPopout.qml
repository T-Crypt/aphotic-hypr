import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property var trayItem

    readonly property var item: trayItem?.modelData ?? null

    spacing: Tokens.spacing.small / 2

    StyledText {
        Layout.maximumWidth: 260
        text: root.item?.tooltipTitle || root.item?.title || root.item?.id || qsTr("Tray item")
        font: Tokens.font.body.medium
        wrapMode: Text.Wrap
    }

    StyledText {
        visible: !!root.item?.tooltipDescription
        Layout.maximumWidth: 260
        text: root.item?.tooltipDescription ?? ""
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
        wrapMode: Text.Wrap
    }

    StyledText {
        Layout.maximumWidth: 260
        text: qsTr("Left-click to activate, right-click for options")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
        wrapMode: Text.Wrap
    }
}
