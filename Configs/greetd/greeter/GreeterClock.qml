import QtQuick

Column {
    id: root

    spacing: 6

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
        font.pixelSize: 112
        font.weight: Font.DemiBold
        font.letterSpacing: -2
        color: Colours.textColor
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root._date.toUpperCase()
        font.pixelSize: 14
        font.weight: Font.DemiBold
        font.letterSpacing: 3
        color: Colours.mutedTextColor
    }
}
