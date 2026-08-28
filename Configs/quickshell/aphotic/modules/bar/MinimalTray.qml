pragma ComponentBehavior: Bound

import "components"
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import qs.config
import qs.components
import qs.services

Item {
    id: root

    property bool expanded: false
    property Item hoveredEntry: null

    readonly property var trayValues: SystemTray.items.values.filter(i => !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))

    implicitWidth: Settings.barHorizontal ? row.implicitWidth : Settings.barInnerWidth
    implicitHeight: Settings.barHorizontal ? Settings.barInnerWidth : row.implicitHeight

    HoverPill {
        container: row
        hoveredEntry: root.hoveredEntry
        thickness: Settings.barHorizontal ? root.height : root.width
    }

    HoverHandler {
        id: rowHover

        onPointChanged: {
            if (!rowHover.hovered)
                return;
            const local = root.mapToItem(row, rowHover.point.position.x, rowHover.point.position.y);
            root.hoveredEntry = BarHit.nearestAt(row, local.x, local.y);
        }
        onHoveredChanged: {
            if (!rowHover.hovered)
                root.hoveredEntry = null;
        }
    }

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            visible: root.trayValues.length > 0
            text: "expand_less"
            rotation: root.expanded ? 180 : 0
            color: Colours.palette.m3onSurfaceVariant

            Behavior on rotation {
                Anim {}
            }

            StateLayer {
                anchors.fill: parent
                anchors.margins: -Tokens.padding.extraSmall
                radius: Tokens.rounding.full
                onClicked: root.expanded = !root.expanded
            }
        }

        Repeater {
            model: root.expanded ? root.trayValues : []

            TrayItem {}
        }
    }
}
