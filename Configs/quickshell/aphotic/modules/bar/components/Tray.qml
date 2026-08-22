pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.config
import qs.components
import qs.services

StyledRect {
    id: root

    readonly property alias layout: layout
    readonly property alias items: items
    readonly property alias expandIcon: expandIcon

    readonly property int padding: Config.bar.tray.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property int spacing: Config.bar.tray.background ? Tokens.spacing.medium : Tokens.spacing.extraSmall

    property bool expanded

    readonly property real nonAnimHeight: {
        if (!Config.bar.tray.compact)
            return layout.implicitHeight + padding * 2;
        const pad = (Config.bar.tray.background ? Tokens.padding.extraSmall : 0) + padding;
        if (expanded)
            return expandIcon.implicitHeight + layout.implicitHeight + spacing + pad;
        return Math.max(Config.bar.tray.background ? width : 0, expandIcon.implicitHeight + pad);
    }

    // Mirrors nonAnimHeight onto the along-axis extent used in horizontal
    // mode -- also read by ActiveWindow.qml's space-accounting when it
    // sits alongside this entry.
    readonly property real nonAnimWidth: {
        if (!Config.bar.tray.compact)
            return layout.implicitWidth + padding * 2;
        const pad = (Config.bar.tray.background ? Tokens.padding.extraSmall : 0) + padding;
        if (expanded)
            return expandIcon.implicitWidth + layout.implicitWidth + spacing + pad;
        return Math.max(Config.bar.tray.background ? height : 0, expandIcon.implicitWidth + pad);
    }

    clip: true
    visible: Settings.barVertical ? width > 0 : height > 0

    implicitWidth: Settings.barVertical ? nonAnimWidth : Settings.barInnerWidth
    implicitHeight: Settings.barVertical ? Settings.barInnerWidth : nonAnimHeight

    color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, items.count > 0 ? 1 : 0)
    radius: Tokens.rounding.full

    Grid {
        id: layout

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Settings.barVertical ? 0 : root.padding
        anchors.leftMargin: Settings.barVertical ? root.padding : 0
        spacing: Tokens.spacing.small

        flow: Settings.barVertical ? Grid.LeftToRight : Grid.TopToBottom
        // Grid (unlike GridLayout) has no "no limit" default for the
        // cross axis, so this is pinned to the actual item count instead
        // of a large constant -- large fixed values overflowed rows *
        // columns into a negative capacity.
        columns: Settings.barVertical ? Math.max(1, items.count) : 1
        rows: Settings.barVertical ? 1 : Math.max(1, items.count)

        opacity: root.expanded || !Config.bar.tray.compact ? 1 : 0

        states: State {
            name: "vertical"
            when: Settings.barVertical

            AnchorChanges {
                target: layout
                anchors.horizontalCenter: undefined
                anchors.top: undefined
                anchors.left: root.left
                anchors.verticalCenter: root.verticalCenter
            }
        }

        add: Transition {
            Anim {
                properties: "scale"
                from: 0
                to: 1
                easing: Tokens.anim.standardDecel
            }
        }

        move: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing: Tokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }

        Repeater {
            id: items

            model: ScriptModel {
                values: SystemTray.items.values.filter(i => !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))
            }

            TrayItem {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: expandIcon

        asynchronous: true

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom

        active: Config.bar.tray.compact && items.count > 0

        states: State {
            name: "vertical"
            when: Settings.barVertical

            AnchorChanges {
                target: expandIcon
                anchors.horizontalCenter: undefined
                anchors.bottom: undefined
                anchors.verticalCenter: root.verticalCenter
                anchors.right: root.right
            }
        }

        sourceComponent: Item {
            implicitWidth: Settings.barVertical ? expandIconInner.implicitWidth - Tokens.padding.small : expandIconInner.implicitWidth
            implicitHeight: Settings.barVertical ? expandIconInner.implicitHeight : expandIconInner.implicitHeight - Tokens.padding.small

            MaterialIcon {
                id: expandIconInner

                anchors.horizontalCenter: Settings.barVertical ? undefined : parent.horizontalCenter
                anchors.bottom: Settings.barVertical ? undefined : parent.bottom
                anchors.verticalCenter: Settings.barVertical ? parent.verticalCenter : undefined
                anchors.right: Settings.barVertical ? parent.right : undefined
                anchors.bottomMargin: Settings.barVertical ? 0 : (Config.bar.tray.background ? Tokens.padding.extraSmall : -Tokens.padding.small)
                anchors.rightMargin: Settings.barVertical ? (Config.bar.tray.background ? Tokens.padding.extraSmall : -Tokens.padding.small) : 0
                // Collapsed: point toward the leading edge items expand
                // from (up when stacked top-down, left when laid out
                // left-to-right). Expanded: point away, toward where the
                // items now are.
                rotation: Settings.barVertical ? (root.expanded ? 90 : -90) : (root.expanded ? 180 : 0)
                text: "expand_less"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium

                Behavior on rotation {
                    Anim {}
                }

                Behavior on anchors.bottomMargin {
                    Anim {}
                }

                Behavior on anchors.rightMargin {
                    Anim {}
                }
            }
        }
    }

    Behavior on implicitHeight {
        Anim {}
    }

    Behavior on implicitWidth {
        Anim {}
    }
}
