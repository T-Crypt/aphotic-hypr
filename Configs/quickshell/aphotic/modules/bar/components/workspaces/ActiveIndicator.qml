pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.components.effects
import qs.services

Item {
    id: root

    required property int activeWsId
    required property Repeater workspaces
    required property Item mask
    required property bool fullscreen

    // workspaces.count, not Config.bar.workspaces.shown: the row shows
    // fewer cells than configured when Bar.qml's sizing budget can't fit
    // them all (see Workspaces.qml's effectiveShown), and this index has to
    // wrap on what is actually rendered or it points at a cell that isn't
    // there.
    readonly property int shown: Math.max(1, workspaces.count)
    readonly property int currentWsIdx: {
        let i = activeWsId - 1;
        while (i < 0)
            i += shown;
        return i % shown;
    }

    property real leading: workspaces.count > 0 ? (Settings.barHorizontal ? workspaces.itemAt(currentWsIdx)?.x ?? 0 : workspaces.itemAt(currentWsIdx)?.y ?? 0) : 0
    property real trailing: workspaces.count > 0 ? (Settings.barHorizontal ? workspaces.itemAt(currentWsIdx)?.x ?? 0 : workspaces.itemAt(currentWsIdx)?.y ?? 0) : 0
    property real currentSize: workspaces.count > 0 ? (workspaces.itemAt(currentWsIdx) as Workspace)?.size ?? 0 : 0
    property real offset: Math.min(leading, trailing)
    property real size: {
        const s = Math.abs(leading - trailing) + currentSize;
        if (Config.bar.workspaces.activeTrail && lastWs > currentWsIdx) {
            const ws = workspaces.itemAt(lastWs) as Workspace;
            const wsAlong = ws ? (Settings.barHorizontal ? ws.x : ws.y) : 0;
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

    x: Settings.barHorizontal ? offset + mask.x : 0
    y: Settings.barHorizontal ? 0 : offset + mask.y
    implicitWidth: Settings.barHorizontal ? size : (Settings.barInnerWidth - Tokens.padding.small)
    implicitHeight: Settings.barHorizontal ? (Settings.barInnerWidth - Tokens.padding.small) : size

    // The pill has to clip: `colouriser` below renders the WHOLE workspace
    // row and slides it under this window so only the active cell's glyph
    // shows through. Item.clip is a rectangular scissor that ignores
    // `radius`, though, so this used to be one StyledRect with clip:true
    // holding both the glow and the glyph -- which sliced the glow's soft
    // falloff off at the pill's square bounding box and read as a hard
    // edge against every other soft-rounded thing on the bar.
    //
    // So the glow sits outside the clip now, and the clip itself is a
    // rounded one. This is also the z-order BioluminescentGlow documents:
    // glow first, target painting over it to hide the solid core.
    BioluminescentGlow {
        target: pill
    }

    StyledClippingRect {
        id: pill

        anchors.fill: parent
        radius: Tokens.rounding.full
        color: Colours.palette.m3primary

        Colouriser {
            id: colouriser

            source: root.mask
            sourceColor: Colours.palette.m3onSurface
            colorizationColor: Colours.palette.m3onPrimary

            x: Settings.barHorizontal ? -root.offset : 0
            y: Settings.barHorizontal ? 0 : -root.offset
            implicitWidth: root.mask.implicitWidth
            implicitHeight: root.mask.implicitHeight

            anchors.horizontalCenter: parent.horizontalCenter

            states: State {
                name: "vertical"
                when: Settings.barHorizontal

                AnchorChanges {
                    target: colouriser
                    anchors.horizontalCenter: undefined
                    anchors.verticalCenter: parent.verticalCenter
                }
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
