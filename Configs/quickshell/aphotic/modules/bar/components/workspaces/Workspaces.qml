pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.modules.bar.components

StyledClippingRect {
    id: root

    required property ShellScreen screen
    required property bool fullscreen

    readonly property bool onSpecial: (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? Hypr.monitorFor(screen) : Hypr.focusedMonitor)?.lastIpcObject.specialWorkspace?.name !== ""
    readonly property int activeWsId: GlobalConfig.bar.workspaces.perMonitorWorkspaces ? (Hypr.monitorFor(screen).activeWorkspace?.id ?? 1) : Hypr.activeWsId

    readonly property var occupied: {
        const occ = {};
        for (const ws of Hypr.workspaces.values)
            occ[ws.id] = ws.lastIpcObject.windows > 0;
        return occ;
    }
    readonly property int groupOffset: Math.floor((activeWsId - 1) / effectiveShown) * effectiveShown

    property real blur: onSpecial ? 1 : 0
    // Whichever cell the pointer is nearest, occupied or not -- an empty
    // workspace is still somewhere you can switch to, so it highlights the
    // same as a busy one.
    property Item hoveredWorkspace: null

    // ---- Window-icon budget --------------------------------------------
    //
    // Along-axis room granted by Bar.qml's sizing budget; -1 = no budget in
    // force (any host that isn't Bar.qml). The workspace row is the single
    // most volatile entry in the bar: with the defaults (5 shown, up to 5
    // window icons each) it swings roughly 220px to 700px purely on which
    // apps happen to be open, which is what used to shove the entries below
    // it off the end of the strip.
    //
    // So the icons are treated as optional detail with a real budget:
    // baseExtent is what the row needs with no icons at all, desiredExtent
    // is what it would take to show every icon it wants, and whatever the
    // bar can actually spare in between is shared out round-robin -- every
    // occupied workspace gets its 1st icon before any gets its 2nd. A
    // crowded bar thins every workspace evenly instead of letting one busy
    // workspace eat the room the clock and power button needed.
    property real maxExtent: -1
    // Room granted for the CELLS alone, before any window icons (Bar.qml's
    // structuralAlong). effectiveShown must be decided from this and not
    // from maxExtent: the icon demand that maxExtent is computed from is
    // itself measured per visible cell, so the round trip would be a
    // binding loop.
    property real structureExtent: -1

    readonly property int shown: Config.bar.workspaces.shown
    // How many cells actually fit in the room the bar granted. Config's
    // `shown` is the number the user asked for; on a bar too short to hold
    // them all this paginates instead -- the group-of-N stepping that
    // groupOffset already implements just steps by a smaller N. Only the
    // truly over-full case ever moves this off `shown`.
    readonly property int effectiveShown: structureExtent < 0 ? shown : Math.max(1, Math.min(shown, Math.floor((structureExtent - Tokens.padding.small + wsSpacing) / (cellExtent + wsSpacing))))
    readonly property int wsSpacing: Math.floor(Tokens.spacing.extraSmall)
    // Workspace.qml pins its number/dot to exactly this along-axis size, so
    // this is a real constant of the layout rather than a value measured
    // back off the rendered row.
    readonly property int cellExtent: Settings.barInnerWidth - Tokens.padding.small

    // Window counts for the currently shown group, already capped at the
    // configured per-workspace ceiling. Read straight off Hypr rather than
    // off the rendered delegates, so the budget never depends on the sizes
    // it is about to decide.
    readonly property var windowDemand: {
        const counts = new Array(effectiveShown).fill(0);
        if (!Config.bar.workspaces.showWindows)
            return counts;
        for (const c of Hypr.toplevels.values) {
            const idx = (c.workspace?.id ?? -1) - 1 - groupOffset;
            if (idx >= 0 && idx < counts.length)
                counts[idx]++;
        }
        const cap = Config.bar.workspaces.maxWindowIcons;
        return cap > 0 ? counts.map(n => Math.min(n, cap)) : counts;
    }
    readonly property int demandedIcons: windowDemand.reduce((acc, n) => acc + n, 0)

    function cellsExtent(cells: int): int {
        return cells * cellExtent + wsSpacing * Math.max(0, cells - 1) + Tokens.padding.small;
    }

    // One cell -- the active workspace -- is the least this row can show and
    // still mean anything. min and base are both pure functions of config,
    // never of what the row was granted: they are the inputs to that
    // decision, so anything they read must sit upstream of it.
    readonly property int minExtent: cellsExtent(1)
    readonly property int baseExtent: cellsExtent(shown)
    // Workspace.qml adds one extraSmall pad to any workspace actually
    // drawing icons, so the icons cost that as well as their own extent.
    readonly property int iconPadding: windowDemand.filter(n => n > 0).length * Tokens.padding.extraSmall
    readonly property int desiredExtent: baseExtent + iconPadding + demandedIcons * iconExtent
    readonly property int iconExtent: Math.max(1, Settings.barHorizontal ? iconMetric.implicitWidth : iconMetric.implicitHeight)

    readonly property int iconBudget: maxExtent < 0 ? demandedIcons : Math.max(0, Math.min(demandedIcons, Math.floor((maxExtent - cellsExtent(effectiveShown) - iconPadding) / iconExtent)))

    // Round-robin share-out: hand every workspace its Nth icon before any
    // workspace gets its (N+1)th.
    readonly property var iconAllowance: {
        const want = windowDemand;
        const out = new Array(want.length).fill(0);
        let left = iconBudget;
        for (let round = 0; left > 0; round++) {
            let progressed = false;
            for (let i = 0; i < want.length && left > 0; i++) {
                if (want[i] > round) {
                    out[i]++;
                    left--;
                    progressed = true;
                }
            }
            if (!progressed)
                break;
        }
        return out;
    }

    // Measures one real MaterialIcon of exactly the kind Workspace.qml
    // renders, so iconExtent above is the true rendered extent rather than
    // a guessed constant that would silently drift with the icon font.
    MaterialIcon {
        id: iconMetric

        visible: false
        text: "terminal"
    }

    implicitWidth: Settings.barHorizontal ? layout.implicitWidth + Tokens.padding.small : Settings.barInnerWidth
    implicitHeight: Settings.barHorizontal ? Settings.barInnerWidth : layout.implicitHeight + Tokens.padding.small

    color: Colours.palette.m3surfaceContainerHigh
    radius: Tokens.rounding.full

    Item {
        anchors.fill: parent
        scale: root.onSpecial ? 0.8 : 1
        opacity: root.onSpecial ? 0.5 : 1
        visible: !root.fullscreen

        layer.enabled: root.blur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: root.blur
            blurMax: 32
        }

        Loader {
            asynchronous: true
            active: Config.bar.workspaces.occupiedBg

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall

            sourceComponent: OccupiedBg {
                workspaces: workspaces
                occupied: root.occupied
                groupOffset: root.groupOffset
            }
        }

        HoverPill {
            container: layout
            hoveredEntry: root.hoveredWorkspace
            thickness: Settings.barHorizontal ? parent.height : parent.width
        }

        GridLayout {
            id: layout

            anchors.centerIn: parent
            flow: Settings.barHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
            rowSpacing: Math.floor(Tokens.spacing.extraSmall)
            columnSpacing: Math.floor(Tokens.spacing.extraSmall)

            Repeater {
                id: workspaces

                model: root.effectiveShown

                Workspace {
                    activeWsId: root.activeWsId
                    occupied: root.occupied
                    groupOffset: root.groupOffset
                    maxIcons: root.iconAllowance[index] ?? 0
                }
            }
        }

        Loader {
            id: activeIndicatorLoader

            asynchronous: true
            anchors.horizontalCenter: parent.horizontalCenter
            active: Config.bar.workspaces.activeIndicator

            states: State {
                name: "vertical"
                when: Settings.barHorizontal

                AnchorChanges {
                    target: activeIndicatorLoader
                    anchors.horizontalCenter: undefined
                    anchors.verticalCenter: activeIndicatorLoader.parent.verticalCenter
                }
            }

            sourceComponent: ActiveIndicator {
                activeWsId: root.activeWsId
                workspaces: workspaces
                mask: layout
                fullscreen: root.fullscreen
            }
        }

        MouseArea {
            anchors.fill: layout
            hoverEnabled: true

            onPositionChanged: event => root.hoveredWorkspace = BarHit.nearestAt(layout, event.x, event.y)
            onExited: root.hoveredWorkspace = null
            // Nearest-centre, matching the hover highlight -- childAt()
            // returns nothing in the gap between two cells, so a click
            // landing where the highlight clearly showed a target used to
            // do nothing at all.
            onClicked: event => {
                const ws = (BarHit.nearestAt(layout, event.x, event.y) as Workspace)?.ws;
                if (!ws)
                    return;
                if (Hypr.activeWsId !== ws)
                    Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = "${ws}" })` : `workspace ${ws}`);
                else
                    Hypr.dispatch(Hypr.usingLua ? 'hl.dsp.workspace.toggle_special("special")' : "togglespecialworkspace special");
            }
        }

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: specialWs

        asynchronous: true

        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall

        active: opacity > 0

        scale: root.onSpecial ? 1 : 0.5
        opacity: root.onSpecial ? 1 : 0

        sourceComponent: SpecialWorkspaces {
            screen: root.screen
        }

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Behavior on blur {
        Anim {
            type: Anim.StandardSmall
        }
    }
}
