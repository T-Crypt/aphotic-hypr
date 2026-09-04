pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen

    signal switched

    readonly property int activeWsId: GlobalConfig.bar.workspaces.perMonitorWorkspaces ? (Hypr.monitorFor(screen).activeWorkspace?.id ?? 1) : Hypr.activeWsId
    readonly property var occupied: {
        const occ = {};
        for (const ws of Hypr.workspaces.values)
            occ[ws.id] = ws.lastIpcObject.windows > 0;
        return occ;
    }

    readonly property int cell: 20

    implicitWidth: cells.implicitWidth
    implicitHeight: cells.implicitHeight

    onActiveWsIdChanged: root.switched()

    GridLayout {
        id: cells

        anchors.centerIn: parent
        flow: Settings.barHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
        rowSpacing: 2
        columnSpacing: 2

        Repeater {
            model: Config.bar.workspaces.shown

            Item {
                id: slot

                required property int index
                readonly property int wsId: slot.index + 1
                readonly property bool isActive: slot.wsId === root.activeWsId
                readonly property bool isOccupied: !!root.occupied[slot.wsId]

                implicitWidth: root.cell
                implicitHeight: root.cell

                HoverHandler {
                    id: slotHover
                }

                StyledRect {
                    id: pip

                    anchors.centerIn: parent

                    readonly property real base: slot.isActive ? 16 : (slot.isOccupied ? 9 : 7)

                    width: pip.base
                    height: pip.base
                    // A rounded square rotated off-axis reads as a shape
                    // change rather than a size change, without costing a
                    // path rebuild the way a real morph would.
                    radius: slot.isActive ? 5 : pip.base / 2
                    rotation: slot.isActive ? (slotHover.hovered ? -12 : 16) : (slotHover.hovered ? 12 : 0)
                    scale: slotHover.hovered ? 1.18 : 1
                    color: slot.isActive ? Colours.palette.m3primary : (slot.isOccupied ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3outlineVariant)
                    opacity: slot.isActive ? 1 : (slot.isOccupied ? 0.8 : 0.45)

                    Behavior on width {
                        enabled: Settings.capsuleAnimations
                        Anim { type: Anim.FastSpatial }
                    }
                    Behavior on height {
                        enabled: Settings.capsuleAnimations
                        Anim { type: Anim.FastSpatial }
                    }
                    Behavior on radius {
                        enabled: Settings.capsuleAnimations
                        Anim { type: Anim.FastSpatial }
                    }
                    Behavior on rotation {
                        enabled: Settings.capsuleAnimations
                        Anim { type: Anim.FastSpatial }
                    }
                    Behavior on scale {
                        enabled: Settings.capsuleAnimations
                        Anim { type: Anim.FastEffects }
                    }
                    Behavior on opacity {
                        enabled: Settings.capsuleAnimations
                        Anim { type: Anim.FastEffects }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (slot.isActive)
                            return;
                        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = ${slot.wsId} })` : `workspace ${slot.wsId}`);
                    }
                }
            }
        }
    }
}
