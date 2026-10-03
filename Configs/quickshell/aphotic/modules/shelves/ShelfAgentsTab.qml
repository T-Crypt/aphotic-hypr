pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.services.ai

// Harness sessions, read from the one shared feed. Holding it is what
// starts the tail, so an unopened tab runs nothing: the hold is taken in
// Component.onCompleted and released in Component.onDestruction, which is
// exactly the lifetime of the tab.
Flickable {
    id: root

    contentWidth: width
    contentHeight: layout.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    required property string owner
    readonly property var sessions: AgentEvents.liveSessions

    Component.onCompleted: AgentEvents.hold(root.owner,true)
    Component.onDestruction: AgentEvents.hold(root.owner,false)

    ColumnLayout {
        id: layout

        width: root.width
        spacing: Tokens.spacing.extraSmall

        Repeater {
            model: root.sessions
            delegate: Item {
                id: row

                required property var modelData

                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.small
                Layout.rightMargin: Tokens.padding.small
                implicitHeight: 40

                RowLayout {
                    anchors.fill: parent
                    spacing: Tokens.spacing.small

                    StyledRect {
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: Tokens.rounding.full
                        color: row.modelData.status === "waiting" ? Colours.palette.m3tertiary : Colours.palette.m3primary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.title ?? row.modelData.harness
                            elide: Text.ElideRight
                            font: Tokens.font.label.small
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.status
                            elide: Text.ElideRight
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                    }
                }
            }
        }

        StyledText {
            visible: root.sessions.length === 0
            Layout.fillWidth: true
            Layout.margins: Tokens.padding.small
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("No live agent sessions")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }
    }
}