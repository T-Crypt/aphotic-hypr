pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.services.ai

Item {
    id: root

    readonly property var activeSession: IntelligenceSessions.activeSession
    readonly property bool thisSessionBusy: AiProviders.busy && root.activeSession !== null && AiProviders.activeRequestId === root.activeSession.id

    // Splits a message on fenced ```code``` blocks so the bubble delegate
    // can render code in a monospace block instead of wrapping it as plain
    // prose -- deliberately minimal (no inline-code spans, bold/italic,
    // lists, headers): this is markdown-LITE, not a full renderer.
    function segments(text: string): var {
        const parts = [];
        const re = /```[a-zA-Z0-9_+-]*\n([\s\S]*?)```/g;
        let last = 0;
        let m;
        while ((m = re.exec(text)) !== null) {
            if (m.index > last)
                parts.push({ code: false, content: text.slice(last, m.index) });
            parts.push({ code: true, content: m[1].replace(/\n$/, "") });
            last = re.lastIndex;
        }
        if (last < text.length)
            parts.push({ code: false, content: text.slice(last) });
        return parts.length > 0 ? parts : [{ code: false, content: text }];
    }

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        MouseArea {
            anchors.fill: parent
            z: -1
        }

        ListView {
            id: list

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            clip: true
            spacing: Tokens.spacing.small

            model: root.activeSession?.messages ?? []

            delegate: StyledRect {
                id: bubble

                required property var modelData
                readonly property bool fromUser: bubble.modelData.role === "user"

                width: list.width
                implicitHeight: bubbleColumn.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.medium
                color: bubble.fromUser ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh

                ColumnLayout {
                    id: bubbleColumn

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: Tokens.padding.medium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: root.segments(bubble.modelData.text)

                        ColumnLayout {
                            id: seg

                            required property var modelData

                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                visible: !seg.modelData.code
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: seg.modelData.content
                                color: bubble.fromUser ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurface
                                font: Tokens.font.body.medium
                            }

                            StyledRect {
                                visible: seg.modelData.code
                                Layout.fillWidth: true
                                implicitHeight: seg.modelData.code ? codeText.implicitHeight + Tokens.padding.small * 2 : 0
                                radius: Tokens.rounding.small
                                color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                                StyledText {
                                    id: codeText
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.margins: Tokens.padding.small
                                    wrapMode: Text.WrapAnywhere
                                    text: seg.modelData.content
                                    color: Colours.palette.m3onSurface
                                    font: Tokens.font.mono.small
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: list.count === 0
                anchors.centerIn: parent
                text: qsTr("Ask anything")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }

            StyledText {
                visible: root.thisSessionBusy
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                text: qsTr("Thinking…")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }
    }

    Connections {
        target: IntelligenceSessions
        function onSessionsChanged() {
            Qt.callLater(() => list.positionViewAtEnd());
        }
    }
}
