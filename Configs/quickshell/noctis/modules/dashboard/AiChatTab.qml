import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    Layout.preferredWidth: 480
    Layout.preferredHeight: 300

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillHeight: true
        verticalAlignment: Text.AlignVCenter
        text: qsTr("AI Chat — coming soon")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.medium
    }
}
