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
    // Read by ActiveWindow.qml to work out how much room its own entry has
    // left along the bar.
    readonly property real spacing: Tokens.spacing.extraSmall

    // The active layout's Repeater, whichever orientation is live -- both
    // closeTray() and the along-axis helpers below hit-test/iterate through
    // this rather than root's own direct children, since the entries now
    // live one level deeper (root -> Loader -> Row/ColumnLayout -> entry).
    readonly property Item activeLayout: Settings.barVertical ? hLoader.item : vLoader.item
    readonly property Repeater activeRepeater: activeLayout?.repeater ?? null

    implicitWidth: Settings.barVertical ? (activeLayout?.implicitWidth ?? 0) : thickness
    implicitHeight: Settings.barVertical ? thickness : (activeLayout?.implicitHeight ?? 0)
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
        return Settings.barVertical ? Qt.point(pos, height / 2) : Qt.point(width / 2, pos);
    }

    // Nearest-center hit-test rather than an exact childAt() rect test --
    // childAt() returns null the instant the cursor sits in the (small
    // but real) gap/margin between two adjacent entries, which is exactly
    // where a cursor moving along a tightly-packed row of icons (the
    // status icons: wifi, bluetooth, battery, resources) spends a lot of
    // its time. A null hit left checkPopout() falling through without
    // updating anything, so the PREVIOUS popout just stuck around and
    // then snapped to the new one once the cursor cleared the gap --
    // reading as an inconsistent, sometimes-from-above/sometimes-from-
    // below jump rather than a clean, direct move. Picking whichever
    // child's center is closest guarantees a hit everywhere, with the
    // switch-over happening exactly at each pair's midpoint instead of a
    // dead zone.
    function nearestAlongChild(container: Item, pos: real): var {
        if (!container)
            return null;
        let best = null;
        let bestDist = Infinity;
        for (const child of container.children) {
            const size = Settings.barVertical ? child.width : child.height;
            if (size <= 0)
                continue;
            const start = Settings.barVertical ? child.x : child.y;
            const dist = Math.abs(start + size / 2 - pos);
            if (dist < bestDist) {
                bestDist = dist;
                best = child;
            }
        }
        return best;
    }

    function childAlong(pos: real): EntryWrapper {
        return root.nearestAlongChild(activeLayout, pos) as EntryWrapper;
    }

    function centerAlong(item: Item): real {
        const c = Settings.barVertical ? item.mapToItem(activeLayout, item.implicitWidth / 2, 0) : item.mapToItem(activeLayout, 0, item.implicitHeight / 2);
        return Settings.barVertical ? c.x : c.y;
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
        const top = Settings.barVertical ? ch.x : ch.y;

        if (id === "statusIcons" && Config.bar.popouts.statusIcons) {
            // Tightly scoped to whichever pill (Connectivity/System/
            // Notifications) the pointer is actually within -- hovering
            // the gap between two pills clears the popout instead of
            // resolving to whichever pill happens to be nearest.
            const groups = (ch.item as StatusIcons).groupContainers;
            let matched = null;
            for (const g of groups) {
                const local = Settings.barVertical ? activeLayout.mapToItem(g.pill, pos, 0).x : activeLayout.mapToItem(g.pill, 0, pos).y;
                const size = Settings.barVertical ? g.pill.width : g.pill.height;
                if (local >= 0 && local <= size) {
                    matched = g;
                    break;
                }
            }
            if (matched) {
                const localAlong = Settings.barVertical ? activeLayout.mapToItem(matched.icons, pos, 0).x : activeLayout.mapToItem(matched.icons, 0, pos).y;
                const icon = root.nearestAlongChild(matched.icons, localAlong);
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
                const trayExtent = Settings.barVertical ? tray.layout.implicitWidth : tray.layout.implicitHeight;
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
        } else if (pos < (Settings.barVertical ? screen.width : screen.height) / 2 && Config.bar.scrollActions.volume) {
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
        active: !Settings.barVertical

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
        active: Settings.barVertical

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
                    Layout.fillWidth: Settings.barVertical
                    Layout.fillHeight: !Settings.barVertical
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
                    implicitWidth: Settings.barVertical ? Tokens.spacing.large : 1
                    implicitHeight: Settings.barVertical ? 1 : Tokens.spacing.large
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
                    Workspaces {
                        objectName: "taskbarWorkspaces"
                        screen: root.screen
                        fullscreen: root.fullscreen
                    }
                }
            }
            DelegateChoice {
                roleValue: "activeWindow"
                delegate: EntryWrapper {
                    ActiveWindow {
                        objectName: "taskbarActiveWindow"
                        bar: root
                        monitor: Brightness.getMonitorForScreen(root.screen)
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
        required property var modelData
        required property int index
        default property Item item
        readonly property string entryId: modelData.id

        Layout.topMargin: !Settings.barVertical && index === 0 ? root.vPadding : 0
        Layout.bottomMargin: !Settings.barVertical && index === root.activeRepeater.count - 1 ? root.vPadding : 0
        Layout.leftMargin: Settings.barVertical && index === 0 ? root.vPadding : 0
        Layout.rightMargin: Settings.barVertical && index === root.activeRepeater.count - 1 ? root.vPadding : 0
        Layout.alignment: Settings.barVertical ? Qt.AlignVCenter : Qt.AlignHCenter

        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0

        children: item
    }
}
