pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

RowLayout {
    id: root

    required property ShellScreen screen

    spacing: Tokens.spacing.extraSmall

    readonly property int activeWsId: GlobalConfig.bar.workspaces.perMonitorWorkspaces ? (Hypr.monitorFor(screen).activeWorkspace?.id ?? 1) : Hypr.activeWsId
    readonly property var occupied: {
        const occ = {};
        for (const ws of Hypr.workspaces.values)
            occ[ws.id] = ws.lastIpcObject.windows > 0;
        return occ;
    }

    Repeater {
        model: Config.bar.workspaces.shown

        Rectangle {
            id: dot

            required property int index
            readonly property int wsId: index + 1
            readonly property bool active: wsId === root.activeWsId
            readonly property bool isOccupied: !!root.occupied[wsId]

            Layout.preferredWidth: active ? 14 : 6
            Layout.preferredHeight: 6
            radius: 3
            color: active ? Colours.palette.m3primary : (isOccupied ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3outlineVariant)

            Behavior on Layout.preferredWidth {
                Anim {}
            }

            MouseArea {
                anchors.fill: parent
                onClicked: Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = ${dot.wsId} })` : `workspace ${dot.wsId}`)
            }
        }
    }
}
