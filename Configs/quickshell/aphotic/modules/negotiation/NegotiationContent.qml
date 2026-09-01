pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.services.profile

// The one negotiation prompt every domain pair reuses -- AI vs. Gaming,
// Security vs. Dev, any future pair -- rendered straight off
// ResourceEngine.pending, so no domain plugin builds its own conflict UI.
// The three decisions are the whole contract: nothing here can suspend
// anything by itself, it only reports the answer back to the engine.
Item {
    id: root

    readonly property var negotiation: ResourceEngine.pending
    readonly property bool open: root.negotiation !== null

    readonly property int cardWidth: 520

    implicitWidth: root.cardWidth
    implicitHeight: card.implicitHeight
    width: root.implicitWidth
    height: root.implicitHeight

    function amountText(claim: var): string {
        if (!claim || claim.amount <= 0)
            return "";
        const unit = root.negotiation?.unit ?? "";
        return unit ? `${claim.amount} ${unit} of ` : "";
    }

    StyledRect {
        id: card

        width: root.width
        implicitHeight: column.implicitHeight + Tokens.padding.extraLarge * 2

        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.96
        transformOrigin: Item.Center

        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer
        border.width: Config.border.thickness
        border.color: Colours.palette.m3outlineVariant

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

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: column

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraLarge
            spacing: Tokens.spacing.large

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "swap_horiz"
                    fontStyle: Tokens.font.icon.large
                    color: Colours.palette.m3primary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("%1 Resource Conflict").arg(root.negotiation?.requestor.owner ?? "")
                    font: Tokens.font.title.large
                    elide: Text.ElideRight
                }

                StyledText {
                    visible: ResourceEngine.pendingCount > 1
                    text: qsTr("+%1 more").arg(ResourceEngine.pendingCount - 1)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("%1 is currently using %2%3.").arg(root.negotiation?.claimant.label ?? "").arg(root.amountText(root.negotiation?.claimant ?? null)).arg(root.negotiation?.resourceLabel ?? "")
                    font: Tokens.font.body.medium
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("%1 is requesting %2 at %3 priority.").arg(root.negotiation?.requestor.label ?? "").arg(root.negotiation?.resourceLabel ?? "").arg(root.negotiation?.requestor.priority ?? "")
                    font: Tokens.font.body.medium
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.negotiation?.reason === "capacity"
                    text: qsTr("Combined claims are %1 against a %2 %3 safety budget.").arg(Math.round(root.negotiation?.total ?? 0)).arg(Math.round(root.negotiation?.budget ?? 0)).arg(root.negotiation?.unit ?? "")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                    wrapMode: Text.WordWrap
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Item {
                    Layout.fillWidth: true
                }

                Repeater {
                    model: [
                        {
                            decision: "suspend",
                            label: qsTr("Suspend %1").arg(root.negotiation?.claimant.label ?? ""),
                            filled: true,
                            enabled: root.negotiation?.claimantSuspendable ?? false
                        },
                        {
                            decision: "keep",
                            label: qsTr("Keep Running"),
                            filled: false,
                            enabled: true
                        },
                        {
                            decision: "ignore",
                            label: qsTr("Ignore"),
                            filled: false,
                            enabled: true
                        }
                    ]

                    StyledRect {
                        id: button

                        required property var modelData

                        Layout.preferredWidth: buttonLabel.implicitWidth + Tokens.padding.largeIncreased * 2
                        Layout.preferredHeight: buttonLabel.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        opacity: button.modelData.enabled ? 1 : 0.4
                        color: button.modelData.filled ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

                        StyledText {
                            id: buttonLabel

                            anchors.centerIn: parent
                            text: button.modelData.label
                            color: button.modelData.filled ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurface
                            font: Tokens.font.label.large
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            disabled: !button.modelData.enabled
                            onClicked: ResourceEngine.resolve(button.modelData.decision)
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: !(root.negotiation?.claimantSuspendable ?? false)
                text: qsTr("%1 has no graceful-stop hook, so it can't be suspended from here.").arg(root.negotiation?.claimant.owner ?? "")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
                wrapMode: Text.WordWrap
            }
        }
    }
}
