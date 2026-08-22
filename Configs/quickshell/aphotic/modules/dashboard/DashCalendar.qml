import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    property date viewDate: new Date()

    readonly property int viewMonth: viewDate.getMonth()
    readonly property int viewYear: viewDate.getFullYear()
    readonly property date today: new Date()

    readonly property var weeks: {
        const first = new Date(viewYear, viewMonth, 1);
        const startOffset = first.getDay();
        const daysInMonth = new Date(viewYear, viewMonth + 1, 0).getDate();

        const cells = [];
        for (let i = 0; i < startOffset; i++)
            cells.push(0);
        for (let d = 1; d <= daysInMonth; d++)
            cells.push(d);
        while (cells.length % 7 !== 0)
            cells.push(0);

        const result = [];
        for (let i = 0; i < cells.length; i += 7)
            result.push(cells.slice(i, i + 7));
        return result;
    }

    implicitWidth: 320
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        width: parent.width - Tokens.padding.large * 2
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true

            Item {
                implicitWidth: prevIcon.implicitHeight
                implicitHeight: prevIcon.implicitHeight

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: root.viewDate = new Date(root.viewYear, root.viewMonth - 1, 1)
                }

                MaterialIcon {
                    id: prevIcon
                    anchors.centerIn: parent
                    text: "chevron_left"
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.viewDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                font: Tokens.font.body.large
                color: Colours.palette.m3onSurface
            }

            Item {
                implicitWidth: nextIcon.implicitHeight
                implicitHeight: nextIcon.implicitHeight

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: root.viewDate = new Date(root.viewYear, root.viewMonth + 1, 1)
                }

                MaterialIcon {
                    id: nextIcon
                    anchors.centerIn: parent
                    text: "chevron_right"
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Repeater {
                model: [qsTr("S"), qsTr("M"), qsTr("T"), qsTr("W"), qsTr("T"), qsTr("F"), qsTr("S")]

                StyledText {
                    required property string modelData

                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }
        }

        Repeater {
            model: root.weeks

            RowLayout {
                required property var modelData

                Layout.fillWidth: true

                Repeater {
                    model: parent.modelData

                    Item {
                        id: cell

                        required property int modelData

                        readonly property bool isToday: modelData !== 0 && modelData === root.today.getDate() && root.viewMonth === root.today.getMonth() && root.viewYear === root.today.getFullYear()

                        Layout.fillWidth: true
                        implicitHeight: 32

                        StyledRect {
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            radius: Tokens.rounding.full
                            color: cell.isToday ? Colours.palette.m3primary : "transparent"
                            visible: cell.modelData !== 0

                            StyledText {
                                anchors.centerIn: parent
                                text: cell.modelData
                                color: cell.isToday ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                font: Tokens.font.body.small
                            }
                        }
                    }
                }
            }
        }
    }
}
