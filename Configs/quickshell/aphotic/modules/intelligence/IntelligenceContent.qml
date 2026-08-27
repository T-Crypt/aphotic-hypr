pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.services.ai

Item {
    id: root

    required property ScreenState screenState

    property bool historyOpen: false

    readonly property bool open: root.screenState.intelligence
    readonly property int cardWidth: 460

    implicitWidth: root.cardWidth
    width: root.implicitWidth

    onOpenChanged: {
        if (!root.open)
            root.historyOpen = false;
    }

    state: root.open ? "open" : ""

    states: State {
        name: "open"
        PropertyChanges {
            card.x: 0
            card.opacity: 1
            card.scale: 1
        }
    }

    // Open/close never touch the hosting PanelWindow's own anchors/geometry
    // (see IntelligenceWindow.qml) -- only this content Item's transform
    // animates, on the same emphasized-decelerate/accelerate curves the
    // rest of the shell's overlay chrome uses (Tokens.anim.emphasizedDecel/
    // Accel), just applied here to x/scale/opacity instead of a flyout's
    // width/height morph.
    transitions: [
        Transition {
            from: ""
            to: "open"
            NumberAnimation {
                properties: "x,opacity,scale"
                duration: Tokens.anim.durations.small
                easing: Tokens.anim.emphasizedDecel
            }
        },
        Transition {
            from: "open"
            to: ""
            NumberAnimation {
                properties: "x,opacity,scale"
                duration: Tokens.anim.durations.expressiveFastEffects
                easing: Tokens.anim.emphasizedAccel
            }
        }
    ]

    StyledRect {
        id: card

        width: root.width
        height: root.height
        x: root.cardWidth
        opacity: 0
        scale: 0.96
        transformOrigin: Item.Right

        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: 0.5
            shadowBlur: 0.5
            shadowVerticalOffset: 2
        }

        // Absorbs clicks so a click anywhere on the card (not just on its
        // interactive children) doesn't fall through to the full-screen
        // dismiss MouseArea in IntelligenceWindow underneath.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            IntelligenceHeader {
                Layout.fillWidth: true
                historyOpen: root.historyOpen
                onHistoryToggled: root.historyOpen = !root.historyOpen
                onNewSessionRequested: {
                    root.historyOpen = false;
                    IntelligenceSessions.createSession(Settings.intelligenceDefaultProvider || AiConfig.activeProvider, Settings.intelligenceDefaultModel || AiConfig.ollamaModel);
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                IntelligenceChatView {
                    anchors.fill: parent
                }

                IntelligenceSessionList {
                    anchors.fill: parent
                    open: root.historyOpen
                    onSessionSelected: id => {
                        IntelligenceSessions.switchSession(id);
                        root.historyOpen = false;
                    }
                }
            }

            IntelligenceInput {
                Layout.fillWidth: true
            }
        }
    }
}
