pragma ComponentBehavior: Bound

import "popouts" as BarPopouts
import "components"
import "components/workspaces"
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    required property real thickness
    readonly property int vPadding: Tokens.padding.large
    readonly property real spacing: Tokens.spacing.extraSmall

    // The active layout's Repeater, whichever orientation is live -- both
    // closeTray() and the along-axis helpers below hit-test/iterate through
    // this rather than root's own direct children, since the entries now
    // live one level deeper (root -> Loader -> Row/ColumnLayout -> entry).
    readonly property Item activeLayout: Settings.barHorizontal ? hLoader.item : vLoader.item
    readonly property Repeater activeRepeater: activeLayout?.repeater ?? null

    // ---- Along-axis sizing budget --------------------------------------
    //
    // "Along axis" is the bar's length: the screen's height when docked
    // left/right, its width when docked top/bottom.
    //
    // The budget is derived from the PHYSICAL SCREEN and flows strictly one
    // way:
    //
    //     screen -> contentExtent -> per-entry grant -> the entry's size
    //
    // Nothing to the right of an arrow may feed back into anything to its
    // left. That single rule is the whole fix for the class of bug where a
    // growing entry -- a long window title, an active workspace picking up
    // window icons as apps open on it -- inflated the bar's OWN reported
    // size to make room for itself, and every entry after it got pushed
    // past the bar's vPadding and clean off the bottom/right of the screen.
    // (Reproduced before this change: five windows on the active workspace
    // pushed the power button off a 1080px-tall vertical bar.)
    //
    // Deriving implicitWidth/implicitHeight from activeLayout's own
    // content size -- as this used to -- is exactly that forbidden
    // back-edge, because the layout is simultaneously sized FROM root by
    // the Loaders below.
    readonly property real alongExtent: Settings.barHorizontal ? screen.width : screen.height
    readonly property int entryCount: activeRepeater?.count ?? 0
    readonly property real contentExtent: Math.max(0, alongExtent - vPadding * 2 - spacing * Math.max(0, entryCount - 1))

    // Every entry declares three numbers rather than one implicit size:
    //
    //   minAlong     -- the hard floor. Below this the entry stops being
    //                   worth drawing at all (one workspace cell; an app
    //                   icon with no title).
    //   baseAlong    -- its full STRUCTURE, with every optional detail
    //                   dropped (all configured workspace cells, but no
    //                   window icons).
    //   desiredAlong -- what it would take if the bar were infinitely long.
    //
    // Inelastic entries (logo, clock, tray, status icons, ...) leave all
    // three at their own implicit size and are therefore never asked to
    // give anything up.
    //
    // Room is then handed out as a priority ladder, so the bar sheds detail
    // before it sheds structure:
    //
    //   1. every entry gets its minAlong;
    //   2. what's left goes toward the structural gap (base - min), shared
    //      in proportion to each entry's own gap;
    //   3. only once every base is covered does anything go toward optional
    //      detail (desired - base), shared the same way.
    //
    // Sharing proportionally rather than first-come means two elastic
    // entries degrade together instead of whichever one is listed first
    // eating the room the rest needed.
    readonly property real minTotal: sumOver(w => w.minAlong)
    readonly property real baseTotal: sumOver(w => w.baseAlong)
    readonly property real structuralTotal: sumOver(w => w.structuralDemand)
    readonly property real optionalTotal: sumOver(w => w.optionalDemand)
    readonly property real structuralSlack: Math.max(0, contentExtent - minTotal)
    readonly property real optionalSlack: Math.max(0, contentExtent - baseTotal)

    function sumOver(pick: var): real {
        const rep = activeRepeater;
        if (!rep)
            return 0;
        let total = 0;
        for (let i = 0; i < rep.count; i++) {
            const w = rep.itemAt(i) as EntryWrapper;
            if (w)
                total += pick(w);
        }
        return total;
    }

    // ---- Screen-centering for the active-window pill --------------------
    //
    // The two "spacer" entries flanking "activeWindow" default to an even
    // 50/50 split of whatever room is left, via plain Layout.fillWidth --
    // which only centers the pill within the gap between the workspaces
    // cluster and the tray/clock/status cluster. Those two clusters are
    // rarely the same width (the right side always carries more entries
    // than logo+workspaces on the left), so an even split leaves the pill
    // sitting off true screen-centre by half that difference -- a fixed
    // pixel offset that reads as more of a miss the wider the monitor
    // gets. These properties size the flanking spacers asymmetrically
    // instead, so the pill's own centre lands on alongExtent / 2 -- the
    // screen's actual midpoint -- on any monitor, ultrawide included.
    readonly property int activeWindowIndex: {
        const rep = activeRepeater;
        if (!rep)
            return -1;
        for (let i = 0; i < rep.count; i++) {
            if ((rep.itemAt(i) as EntryWrapper)?.entryId === "activeWindow")
                return i;
        }
        return -1;
    }
    readonly property real activeWindowSlackTotal: Math.max(0, contentExtent - sumOver(w => w.grantedAlong))
    readonly property real activeWindowSlackLeft: {
        if (activeWindowIndex < 0)
            return 0;
        const aw = activeRepeater.itemAt(activeWindowIndex) as EntryWrapper;
        const leftGroupExtent = sumRange(0, activeWindowIndex - 1);
        const ideal = alongExtent / 2 - vPadding - spacing * activeWindowIndex - leftGroupExtent - (aw?.grantedAlong ?? 0) / 2;
        return Math.max(0, Math.min(activeWindowSlackTotal, ideal));
    }
    readonly property real activeWindowSlackRight: activeWindowSlackTotal - activeWindowSlackLeft

    function sumRange(fromIdx: int, toIdxExclusive: int): real {
        const rep = activeRepeater;
        if (!rep)
            return 0;
        let total = 0;
        for (let i = Math.max(0, fromIdx); i < toIdxExclusive; i++) {
            const w = rep.itemAt(i) as EntryWrapper;
            if (w)
                total += w.grantedAlong;
        }
        return total;
    }

    implicitWidth: Settings.barHorizontal ? alongExtent : thickness
    implicitHeight: Settings.barHorizontal ? thickness : alongExtent
    width: implicitWidth
    height: implicitHeight

    function closeTray(): void {
        if (!Config.bar.tray.compact)
            return;

        const rep = activeRepeater;
        if (!rep)
            return;
        for (let i = 0; i < rep.count; i++) {
            const tray = (rep.itemAt(i) as EntryWrapper).item as Tray;
            if (tray)
                tray.expanded = false;
        }
    }

    // "Along axis" is whichever screen dimension the bar's length runs on
    // (y when docked left/right, x when docked top/bottom) -- these three
    // helpers keep checkPopout/handleWheel written in terms of it instead
    // of hardcoding y, so both orientations share the same logic below.
    // All hit-testing/mapping happens against activeLayout rather than
    // root -- root's own (0,0) is the same point as activeLayout's (0,0)
    // (the hosting Loader fills root exactly), so positions received in
    // root's coordinate space (from BarWrapper's HoverHandler/WheelHandler,
    // which target this component) translate directly with no offset.
    function alongPoint(pos: real): point {
        return Settings.barHorizontal ? Qt.point(pos, height / 2) : Qt.point(width / 2, pos);
    }

    function childAlong(pos: real): EntryWrapper {
        return BarHit.nearestAlong(activeLayout, pos) as EntryWrapper;
    }

    function centerAlong(item: Item): real {
        const c = Settings.barHorizontal ? item.mapToItem(activeLayout, item.implicitWidth / 2, 0) : item.mapToItem(activeLayout, 0, item.implicitHeight / 2);
        return Settings.barHorizontal ? c.x : c.y;
    }

    function checkPopout(pos: real): void {
        const ch = childAlong(pos);

        if (ch?.entryId !== "tray")
            closeTray();

        if (!ch) {
            popouts.hasCurrent = false;
            return;
        }

        const id = ch.entryId;
        const top = Settings.barHorizontal ? ch.x : ch.y;

        if (id === "statusIcons" && Config.bar.popouts.statusIcons) {
            // Tightly scoped to whichever pill (Connectivity/System/
            // Notifications) the pointer is actually within -- hovering
            // the gap between two pills clears the popout instead of
            // resolving to whichever pill happens to be nearest.
            const groups = (ch.item as StatusIcons).groupContainers;
            let matched = null;
            for (const g of groups) {
                const local = Settings.barHorizontal ? activeLayout.mapToItem(g.pill, pos, 0).x : activeLayout.mapToItem(g.pill, 0, pos).y;
                const size = Settings.barHorizontal ? g.pill.width : g.pill.height;
                if (local >= 0 && local <= size) {
                    matched = g;
                    break;
                }
            }
            if (matched) {
                const localAlong = Settings.barHorizontal ? activeLayout.mapToItem(matched.icons, pos, 0).x : activeLayout.mapToItem(matched.icons, 0, pos).y;
                const icon = BarHit.nearestAlong(matched.icons, localAlong);
                if (icon) {
                    popouts.currentName = icon.name;
                    popouts.currentCenter = Qt.binding(() => root.centerAlong(icon));
                    popouts.hasCurrent = true;
                } else {
                    popouts.hasCurrent = false;
                }
            } else {
                popouts.hasCurrent = false;
            }
        } else if (id === "tray" && Config.bar.popouts.tray) {
            const tray = ch.item as Tray;
            const hoverPoint = alongPoint(pos);
            const hoveringExpandIcon = tray.expandIcon.contains(activeLayout.mapToItem(tray.expandIcon, hoverPoint.x, hoverPoint.y));
            if (!Config.bar.tray.compact || (tray.expanded && !hoveringExpandIcon)) {
                const trayExtent = Settings.barHorizontal ? tray.layout.implicitWidth : tray.layout.implicitHeight;
                const index = Math.floor(((pos - top - tray.padding * 2 + tray.spacing) / trayExtent) * tray.items.count);
                const trayItem = tray.items.itemAt(index);
                if (trayItem) {
                    popouts.currentName = `traymenu${index}`;
                    popouts.currentTrayItem = trayItem;
                    popouts.currentCenter = Qt.binding(() => root.centerAlong(trayItem));
                    popouts.hasCurrent = true;
                } else {
                    popouts.hasCurrent = false;
                }
            } else {
                popouts.hasCurrent = false;
                tray.expanded = true;
            }
        } else if (id === "activeWindow" && Config.bar.popouts.activeWindow && Config.bar.activeWindow.showOnHover) {
            popouts.currentName = id.toLowerCase();
            popouts.currentCenter = root.centerAlong(ch.item as Item) ?? 0;
            popouts.hasCurrent = true;
        } else if (id === "media" && Config.bar.popouts.media) {
            popouts.currentName = id.toLowerCase();
            popouts.currentCenter = root.centerAlong(ch.item as Item) ?? 0;
            popouts.hasCurrent = true;
        } else if (id === "settings" && Config.bar.popouts.settings) {
            popouts.currentName = id.toLowerCase();
            popouts.currentCenter = root.centerAlong(ch.item as Item) ?? 0;
            popouts.hasCurrent = true;
        } else {
            // Entries with no popout of their own (clock, logo, workspaces,
            // power) -- or one of the ones above with its Config.bar.popouts
            // flag off -- fell through every branch above with nothing to
            // clear hasCurrent, so whatever popout was showing for
            // whichever entry the cursor last hovered stayed stuck on
            // screen (e.g. hovering the clock kept the settings popout
            // open if settings was the last entry actually handled here).
            popouts.hasCurrent = false;
        }
    }

    // Keeps popouts.agentCenter live-anchored to the agent entry's own
    // position regardless of hover -- the agent popout opens on click,
    // not hover, so it needs a stable anchor independent of whatever
    // checkPopout is currently doing. Qt.binding() re-evaluates whenever
    // any property read inside it changes (activeRepeater on an
    // orientation swap, or any sibling entry's own size/position via
    // centerAlong's mapToItem call), so this stays correct without
    // needing to be re-triggered from anywhere else.
    Component.onCompleted: {
        popouts.agentCenter = Qt.binding(() => {
            const rep = root.activeRepeater;
            if (!rep)
                return 0;
            for (let i = 0; i < rep.count; i++) {
                const w = rep.itemAt(i) as EntryWrapper;
                if (w?.entryId === "agent")
                    return root.centerAlong(w.item);
            }
            return 0;
        });
    }

    function handleWheel(pos: real, angleDelta: point): void {
        const ch = childAlong(pos);
        if (ch?.entryId === "workspaces" && Config.bar.scrollActions.workspaces) {
            // Workspace scroll
            const mon = (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? Hypr.monitorFor(screen) : Hypr.focusedMonitor);
            const specialWs = mon?.lastIpcObject.specialWorkspace.name;
            if (specialWs?.length > 0)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.workspace.toggle_special("${specialWs.slice(8)}")` : `togglespecialworkspace ${specialWs.slice(8)}`);
            else if (angleDelta.y < 0 || (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? mon.activeWorkspace?.id : Hypr.activeWsId) > 1)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = "r${angleDelta.y > 0 ? "-" : "+"}1" })` : `workspace r${angleDelta.y > 0 ? "-" : "+"}1`);
        } else if (pos < (Settings.barHorizontal ? screen.width : screen.height) / 2 && Config.bar.scrollActions.volume) {
            // Volume scroll on the half of the bar nearer the screen origin
            if (angleDelta.y > 0)
                Audio.incrementVolume();
            else if (angleDelta.y < 0)
                Audio.decrementVolume();
        } else if (Config.bar.scrollActions.brightness) {
            // Brightness scroll on the other half
            const monitor = Brightness.getMonitorForScreen(screen);
            if (angleDelta.y > 0)
                monitor.setBrightness(monitor.brightness + GlobalConfig.services.brightnessIncrement);
            else if (angleDelta.y < 0)
                monitor.setBrightness(monitor.brightness - GlobalConfig.services.brightnessIncrement);
        }
    }

    // Two separate, mutually-exclusive Loaders (ColumnLayout for the
    // existing left/right dock, RowLayout for the new top/bottom dock)
    // rather than one flow-toggling GridLayout -- GridLayout fought any
    // attempt to externally force its own cross-axis size (collapsed real
    // content down to a couple of px regardless of whether the override
    // came from a plain binding or a Binding{} element), where the
    // specialized Row/ColumnLayout types just accept it, as the original
    // single-orientation code already relied on. Both share the exact
    // entry list via the EntryList component below.
    Loader {
        id: vLoader

        anchors.fill: parent
        active: !Settings.barHorizontal

        sourceComponent: ColumnLayout {
            id: vColumn

            property alias repeater: entryList

            width: root.thickness
            spacing: root.spacing

            EntryList {
                id: entryList
            }
        }
    }

    Loader {
        id: hLoader

        anchors.fill: parent
        active: Settings.barHorizontal

        sourceComponent: RowLayout {
            id: hRow

            property alias repeater: entryList

            height: root.thickness
            spacing: root.spacing

            EntryList {
                id: entryList
            }
        }
    }

    component EntryList: Repeater {
        id: repeater

        model: ScriptModel {
            values: root.Config.bar.entries.values.filter(e => e.enabled)
        }

        DelegateChooser {
            role: "id"

            DelegateChoice {
                roleValue: "spacer"
                delegate: EntryWrapper {
                    // The two spacers flanking "activeWindow" get an
                    // asymmetric split so that entry lands on true
                    // screen-centre (see root.activeWindowSlackLeft/Right);
                    // any other spacer keeps the old even 50/50 fill.
                    readonly property bool centersActiveWindow: root.activeWindowIndex >= 0 && (index === root.activeWindowIndex - 1 || index === root.activeWindowIndex + 1)
                    readonly property real centeringSlack: index === root.activeWindowIndex - 1 ? root.activeWindowSlackLeft : root.activeWindowSlackRight

                    Layout.fillWidth: Settings.barHorizontal && !centersActiveWindow
                    Layout.fillHeight: !Settings.barHorizontal && !centersActiveWindow
                    Layout.preferredWidth: Settings.barHorizontal && centersActiveWindow ? centeringSlack : -1
                    Layout.preferredHeight: !Settings.barHorizontal && centersActiveWindow ? centeringSlack : -1
                }
            }
            DelegateChoice {
                // Fixed-width breathing room, not a greedy fill spacer --
                // separates the status/info cluster (agent, statusIcons)
                // from the settings/power utility actions without
                // competing for leftover space with the existing
                // fillWidth spacers around activeWindow, which would
                // shrink that gap unpredictably to feed this one.
                roleValue: "gap"
                delegate: EntryWrapper {
                    implicitWidth: Settings.barHorizontal ? Tokens.spacing.large : 1
                    implicitHeight: Settings.barHorizontal ? 1 : Tokens.spacing.large
                }
            }
            DelegateChoice {
                roleValue: "logo"
                delegate: EntryWrapper {
                    OsIcon {
                        objectName: "taskbarLogo"
                    }
                }
            }
            DelegateChoice {
                roleValue: "workspaces"
                delegate: EntryWrapper {
                    id: workspacesEntry

                    // Elastic: the workspace row's optional detail is its
                    // per-workspace window icons, which it drops from the
                    // outside in as the bar runs out of room.
                    minAlong: workspacesItem.minExtent
                    baseAlong: workspacesItem.baseExtent
                    desiredAlong: workspacesItem.desiredExtent

                    Workspaces {
                        id: workspacesItem

                        objectName: "taskbarWorkspaces"
                        screen: root.screen
                        fullscreen: root.fullscreen
                        structureExtent: workspacesEntry.structuralAlong
                        maxExtent: workspacesEntry.grantedAlong
                    }
                }
            }
            DelegateChoice {
                roleValue: "activeWindow"
                delegate: EntryWrapper {
                    id: activeWindowEntry

                    // Elastic: the optional detail is the window title,
                    // which elides down to nothing while the app icon
                    // stays.
                    minAlong: activeWindowItem.baseExtent
                    baseAlong: activeWindowItem.baseExtent
                    desiredAlong: activeWindowItem.desiredExtent

                    ActiveWindow {
                        id: activeWindowItem

                        objectName: "taskbarActiveWindow"
                        bar: root
                        monitor: Brightness.getMonitorForScreen(root.screen)
                        maxExtent: activeWindowEntry.grantedAlong
                    }
                }
            }
            DelegateChoice {
                roleValue: "media"
                delegate: EntryWrapper {
                    Media {
                        objectName: "taskbarMedia"
                    }
                }
            }
            DelegateChoice {
                roleValue: "tray"
                delegate: EntryWrapper {
                    Tray {
                        objectName: "taskbarTray"
                    }
                }
            }
            DelegateChoice {
                roleValue: "clock"
                delegate: EntryWrapper {
                    Clock {
                        objectName: "taskbarClock"
                        screenState: root.screenState
                    }
                }
            }
            DelegateChoice {
                roleValue: "statusIcons"
                delegate: EntryWrapper {
                    StatusIcons {
                        objectName: "taskbarStatusIcons"
                        screenState: root.screenState
                    }
                }
            }
            DelegateChoice {
                roleValue: "settings"
                delegate: EntryWrapper {
                    SettingsButton {
                        objectName: "taskbarSettings"
                    }
                }
            }
            DelegateChoice {
                roleValue: "agent"
                delegate: EntryWrapper {
                    AgentIndicator {
                        objectName: "taskbarAgent"
                        screenState: root.screenState
                    }
                }
            }
            DelegateChoice {
                roleValue: "power"
                delegate: EntryWrapper {
                    Power {
                        objectName: "taskbarPowerButton"
                        screenState: root.screenState
                    }
                }
            }
        }
    }

    component EntryWrapper: Item {
        id: entry

        required property var modelData
        required property int index
        default property Item item
        readonly property string entryId: modelData.id

        // See root.minTotal. An elastic entry overrides these with sizes it
        // can work out WITHOUT measuring itself -- reading its own rendered
        // geometry here would re-close the very feedback loop the budget
        // exists to break. An inelastic entry leaves all three equal to its
        // own implicit size and is never asked to shrink.
        property real minAlong: Settings.barHorizontal ? implicitWidth : implicitHeight
        property real baseAlong: minAlong
        property real desiredAlong: baseAlong

        readonly property real structuralDemand: Math.max(0, baseAlong - minAlong)
        readonly property real optionalDemand: Math.max(0, desiredAlong - baseAlong)

        // Rung 1 + 2 of the ladder. Deliberately exposed on its own, and
        // deliberately free of any dependency on desiredAlong: an entry
        // whose STRUCTURE adapts to its allocation (Workspaces dropping
        // cells) must read this one, never grantedAlong -- its own optional
        // demand is measured per visible cell, so feeding the full grant
        // back into that decision is a genuine binding loop, which Qt
        // resolves by freezing the value one evaluation short.
        readonly property real structuralAlong: minAlong + (root.structuralTotal > 0 ? Math.min(structuralDemand, root.structuralSlack * structuralDemand / root.structuralTotal) : 0)
        // Rung 3 on top: optional detail, once every structure is paid for.
        readonly property real grantedAlong: structuralAlong + (root.optionalTotal > 0 ? Math.min(optionalDemand, root.optionalSlack * optionalDemand / root.optionalTotal) : 0)

        // Suppresses the grow-from-zero animation every entry would
        // otherwise play on the bar's first layout pass.
        property bool settled: false

        Layout.topMargin: !Settings.barHorizontal && index === 0 ? root.vPadding : 0
        Layout.bottomMargin: !Settings.barHorizontal && index === root.entryCount - 1 ? root.vPadding : 0
        Layout.leftMargin: Settings.barHorizontal && index === 0 ? root.vPadding : 0
        Layout.rightMargin: Settings.barHorizontal && index === root.entryCount - 1 ? root.vPadding : 0
        Layout.alignment: Settings.barHorizontal ? Qt.AlignVCenter : Qt.AlignHCenter

        // The grant -- never the item's raw implicit size -- is what the
        // layout is asked to allocate along the bar's length, and it is
        // additionally capped at the bar's whole budget so no single entry
        // can ever request more room than the bar physically has. -1 on the
        // cross axis is Layout's own "just use my implicit size".
        Layout.preferredWidth: Settings.barHorizontal ? grantedAlong : -1
        Layout.preferredHeight: Settings.barHorizontal ? -1 : grantedAlong
        Layout.maximumWidth: Settings.barHorizontal ? root.contentExtent : Number.POSITIVE_INFINITY
        Layout.maximumHeight: Settings.barHorizontal ? Number.POSITIVE_INFINITY : root.contentExtent
        // Explicit zero floor along the bar's length. QtQuick.Layouts will
        // happily overflow a layout whose children can't be shrunk below
        // their minimum hint -- the entries would then run straight off the
        // strip again, which is the whole failure this budget exists to
        // prevent. On a bar too short for even every entry's minAlong
        // (many workspaces on a short vertical screen) squeezing is the
        // honest outcome; silently spilling off the edge is not.
        Layout.minimumWidth: Settings.barHorizontal ? 0 : -1
        Layout.minimumHeight: Settings.barHorizontal ? -1 : 0

        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0

        children: item

        Component.onCompleted: settled = true

        // Last line of defence, not the mechanism: hand the child exactly
        // the room it was allocated. When an elastic entry has already
        // reduced itself to its grant this is a no-op -- it only bites when
        // the bar is physically too short for even every entry's base size,
        // where something has to give and silently overlapping neighbours
        // would be worse than one squeezed entry.
        Binding {
            target: entry.item
            property: "width"
            value: entry.width
            when: Settings.barHorizontal && entry.item !== null
            restoreMode: Binding.RestoreBindingOrValue
        }

        Binding {
            target: entry.item
            property: "height"
            value: entry.height
            when: !Settings.barHorizontal && entry.item !== null
            restoreMode: Binding.RestoreBindingOrValue
        }

        Behavior on Layout.preferredWidth {
            enabled: entry.settled && Settings.barHorizontal
            Anim {}
        }

        Behavior on Layout.preferredHeight {
            enabled: entry.settled && !Settings.barHorizontal
            Anim {}
        }
    }
}
