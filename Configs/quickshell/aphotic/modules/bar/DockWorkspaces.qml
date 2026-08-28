pragma ComponentBehavior: Bound

import "components"
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen

    // Overridable so this reads correctly on a solid-accent background
    // (MinimalBar's single-accent-color strip) as well as the neutral
    // surface Dock uses by default.
    property color activeColour: Colours.palette.m3primary
    property color occupiedColour: Colours.palette.m3onSurfaceVariant
    property color emptyColour: Colours.palette.m3outlineVariant

    property Item hoveredEntry: null

    readonly property int dotSize: 6
    readonly property int activeDotSize: 14

    implicitWidth: dots.implicitWidth
    implicitHeight: dots.implicitHeight

    readonly property int activeWsId: GlobalConfig.bar.workspaces.perMonitorWorkspaces ? (Hypr.monitorFor(screen).activeWorkspace?.id ?? 1) : Hypr.activeWsId
    readonly property var occupied: {
        const occ = {};
        for (const ws of Hypr.workspaces.values)
            occ[ws.id] = ws.lastIpcObject.windows > 0;
        return occ;
    }

    HoverHandler {
        id: hover

        onPointChanged: {
            if (!hover.hovered)
                return;
            const local = root.mapToItem(dots, hover.point.position.x, hover.point.position.y);
            root.hoveredEntry = BarHit.nearestAt(dots, local.x, local.y);
        }
        onHoveredChanged: {
            if (!hover.hovered)
                root.hoveredEntry = null;
        }
    }

    // Every other bar style feeds this the strip's own thickness, but a
    // row of dots has none to give -- sized that way the highlight would
    // vanish behind the dot it sits under. Sized off the active dot
    // instead, so it stays legible and stays the same size whichever dot
    // it is over.
    HoverPill {
        container: dots
        hoveredEntry: root.hoveredEntry
        thickness: root.activeDotSize + Tokens.padding.extraSmall
    }

    GridLayout {
        id: dots

        anchors.centerIn: parent
        flow: Settings.barHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
        rowSpacing: Tokens.spacing.extraSmall
        columnSpacing: Tokens.spacing.extraSmall

        Repeater {
            model: Config.bar.workspaces.shown

            Rectangle {
                id: dot

                required property int index
                readonly property int wsId: index + 1
                readonly property bool active: wsId === root.activeWsId
                readonly property bool isOccupied: !!root.occupied[wsId]

                Layout.preferredWidth: Settings.barHorizontal ? (active ? root.activeDotSize : root.dotSize) : root.dotSize
                Layout.preferredHeight: Settings.barHorizontal ? root.dotSize : (active ? root.activeDotSize : root.dotSize)
                radius: root.dotSize / 2
                color: active ? root.activeColour : (isOccupied ? root.occupiedColour : root.emptyColour)

                Behavior on Layout.preferredWidth {
                    Anim {}
                }

                Behavior on Layout.preferredHeight {
                    Anim {}
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = ${dot.wsId} })` : `workspace ${dot.wsId}`)
                }
            }
        }
    }
}
