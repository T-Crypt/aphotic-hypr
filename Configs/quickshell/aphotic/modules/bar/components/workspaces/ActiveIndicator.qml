pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.components.effects
import qs.services

StyledRect {
    id: root

    required property int activeWsId
    required property Repeater workspaces
    required property Item mask
    required property bool fullscreen

    readonly property int currentWsIdx: {
        let i = activeWsId - 1;
        while (i < 0)
            i += Config.bar.workspaces.shown;
        return i % Config.bar.workspaces.shown;
    }

    property real leading: workspaces.count > 0 ? (Settings.barVertical ? workspaces.itemAt(currentWsIdx)?.x ?? 0 : workspaces.itemAt(currentWsIdx)?.y ?? 0) : 0
    property real trailing: workspaces.count > 0 ? (Settings.barVertical ? workspaces.itemAt(currentWsIdx)?.x ?? 0 : workspaces.itemAt(currentWsIdx)?.y ?? 0) : 0
    property real currentSize: workspaces.count > 0 ? (workspaces.itemAt(currentWsIdx) as Workspace)?.size ?? 0 : 0
    property real offset: Math.min(leading, trailing)
    property real size: {
        const s = Math.abs(leading - trailing) + currentSize;
        if (Config.bar.workspaces.activeTrail && lastWs > currentWsIdx) {
            const ws = workspaces.itemAt(lastWs) as Workspace;
            const wsAlong = ws ? (Settings.barVertical ? ws.x : ws.y) : 0;
            return ws ? Math.min(wsAlong + ws.size - offset, s) : 0;
        }
        return s;
    }

    property int cWs
    property int lastWs

    onCurrentWsIdxChanged: {
        lastWs = cWs;
        cWs = currentWsIdx;
    }

    clip: true
    x: Settings.barVertical ? offset + mask.x : 0
    y: Settings.barVertical ? 0 : offset + mask.y
    implicitWidth: Settings.barVertical ? size : (Settings.barInnerWidth - Tokens.padding.small)
    implicitHeight: Settings.barVertical ? (Settings.barInnerWidth - Tokens.padding.small) : size
    radius: Tokens.rounding.full
    color: Colours.palette.m3primary

    Colouriser {
        id: colouriser

        source: root.mask
        sourceColor: Colours.palette.m3onSurface
        colorizationColor: Colours.palette.m3onPrimary

        x: Settings.barVertical ? -parent.offset : 0
        y: Settings.barVertical ? 0 : -parent.offset
        implicitWidth: root.mask.implicitWidth
        implicitHeight: root.mask.implicitHeight

        anchors.horizontalCenter: parent.horizontalCenter

        states: State {
            name: "vertical"
            when: Settings.barVertical

            AnchorChanges {
                target: colouriser
                anchors.horizontalCenter: undefined
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Behavior on leading {
        enabled: root.Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on trailing {
        enabled: root.Config.bar.workspaces.activeTrail

        EAnim {
            duration: Tokens.anim.durations.normal * 2
        }
    }

    Behavior on currentSize {
        enabled: root.Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on offset {
        enabled: !root.Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on size {
        enabled: !root.Config.bar.workspaces.activeTrail

        EAnim {}
    }

    component EAnim: Anim {
        type: Anim.Emphasized
    }
}
