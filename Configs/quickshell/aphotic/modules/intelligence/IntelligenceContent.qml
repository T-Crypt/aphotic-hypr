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

    StyledRect {
        id: card

        width: root.width
        height: root.height
        // Bound directly to root.open with the Behaviors below driving
        // the motion, matching the Behavior-on-property idiom every other
        // popout in this shell uses (see popouts/Wrapper.qml's flyout/
        // agentFlyout) rather than a bespoke state/PropertyChanges/
        // Transition block with its own one-off duration/easing pair.
        x: root.open ? 0 : root.cardWidth
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.96
        transformOrigin: Item.Right

        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer

        Behavior on x {
            Anim {
                type: Anim.Emphasized
            }
        }
        Behavior on opacity {
            Anim {
                type: Anim.Emphasized
            }
        }
        Behavior on scale {
            Anim {
                type: Anim.Emphasized
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: 0.5
            shadowBlur: 0.5
            shadowVerticalOffset: 2
        }

        DepthLayer {
            anchors.fill: parent
            opacityScale: 0.35
        }

        DepthGradient {
            anchors.fill: parent
            radius: card.radius
            baseColour: card.color
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
