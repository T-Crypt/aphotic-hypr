import QtQuick

Column {
    id: root

    spacing: 4

    property string _time: Qt.formatTime(new Date(), "hh:mm")
    property string _date: Qt.formatDate(new Date(), "dddd, MMMM d")

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root._time = Qt.formatTime(new Date(), "hh:mm");
            root._date = Qt.formatDate(new Date(), "dddd, MMMM d");
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root._time
        font.pixelSize: 64
        font.weight: Font.Light
        color: Colours.textColor
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root._date
        font.pixelSize: 18
        color: Colours.mutedTextColor
    }
}
