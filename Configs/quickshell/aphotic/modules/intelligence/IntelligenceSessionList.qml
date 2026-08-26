pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.services.ai

Item {
    id: root

    required property bool open

    signal sessionSelected(id: string)

    visible: opacity > 0
    opacity: root.open ? 1 : 0
    x: root.open ? 0 : -width * 0.1

    Behavior on opacity {
        Anim { type: Anim.Emphasized }
    }
    Behavior on x {
        Anim { type: Anim.Emphasized }
    }

    function relativeTime(ms: real): string {
        const diff = Date.now() - ms;
        const mins = Math.floor(diff / 60000);
        if (mins < 1)
            return qsTr("just now");
        if (mins < 60)
            return qsTr("%1m ago").arg(mins);
        const hours = Math.floor(mins / 60);
        if (hours < 24)
            return qsTr("%1h ago").arg(hours);
        return qsTr("%1d ago").arg(Math.floor(hours / 24));
    }

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.medium
        color: Colours.tPalette.m3surfaceContainer

        MouseArea {
            anchors.fill: parent
        }

        ListView {
            id: list

            anchors.fill: parent
            anchors.margins: Tokens.padding.small
            clip: true
            spacing: Tokens.spacing.extraSmall
            model: IntelligenceSessions.sessions

            delegate: StyledRect {
                id: row

                required property var modelData

                width: list.width
                implicitHeight: 52
                radius: Tokens.rounding.small
                color: row.modelData.id === IntelligenceSessions.activeSessionId ? Colours.layer(Colours.tPalette.m3surfaceContainer, 3) : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    spacing: Tokens.spacing.small

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: row.modelData.title
                            font: Tokens.font.body.small
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: `${row.modelData.provider} · ${root.relativeTime(row.modelData.updatedAt)}`
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                    }

                    MaterialIcon {
                        text: "delete"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            radius: Tokens.rounding.full

                            onClicked: IntelligenceSessions.deleteSession(row.modelData.id)
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onClicked: root.sessionSelected(row.modelData.id)
                }
            }

            StyledText {
                visible: list.count === 0
                anchors.centerIn: parent
                text: qsTr("No conversations yet")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }
        }
    }
}
