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

    readonly property var trayValues: SystemTray.items.values.filter(i => !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row

        anchors.fill: parent
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
