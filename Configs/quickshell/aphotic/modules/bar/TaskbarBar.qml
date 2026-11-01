pragma ComponentBehavior: Bound

import "components"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services
import qs.modules.bar.popouts as BarPopouts
import "../../services/BarLayout.js" as BarLayout

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    required property real thickness

    readonly property string notchEdge: BarLayout.notchEdge(Settings.barHorizontal, Settings.barPositionBottom, Settings.barPositionRight)

    implicitWidth: Settings.barHorizontal ? layout.implicitWidth + Tokens.padding.medium * 2 : thickness
    implicitHeight: Settings.barHorizontal ? thickness : layout.implicitHeight + Tokens.padding.medium * 2

    // The one task pill holding a focused window, if any -- the strip's
    // Signal line puts its accent segment under it.
    readonly property Item focusedTaskItem: layout.children.find(c => c.isTaskItem && c.focused) || null

    function closeTray(): void {
        tray.expanded = false;
    }

    function centerAlong(item: Item): real {
        return Settings.barHorizontal ? item.mapToItem(root, item.implicitWidth / 2, 0).x : item.mapToItem(root, 0, item.implicitHeight / 2).y;
    }

    // `pos` along the bar's axis, mapped from layout into `target`.
    function alongIn(target: Item, pos: real): real {
        return Settings.barHorizontal ? layout.mapToItem(target, pos, 0).x : layout.mapToItem(target, 0, pos).y;
    }

    function pointAt(pos: real): point {
        return Settings.barHorizontal ? Qt.point(pos, 0) : Qt.point(0, pos);
    }

    // Same region-hysteresis lock as Bar.qml's checkPopout -- see that
    // file's comment for the full reasoning (reported live as "hovering
    // too long makes the popout stop appearing/updating", root-caused to
    // a single borderline sample -- between two pills, between two tray
    // icons -- tripping an explicit hasCurrent = false even while the
    // pointer was still squarely over the same bar child the whole time).
    // TaskbarBar duplicates Bar.qml's hit-testing by hand (see the
    // existing note in docs about this being a copy, not shared), so the
    // fix has to be duplicated too.
    readonly property real regionHysteresisMargin: 4
    property Item _lockedChild: null

    function withinLockedRegion(localPos: real): bool {
        if (!_lockedChild)
            return false;
        const start = Settings.barHorizontal ? _lockedChild.x : _lockedChild.y;
        const size = Settings.barHorizontal ? _lockedChild.width : _lockedChild.height;
        return localPos >= start - regionHysteresisMargin && localPos <= start + size + regionHysteresisMargin;
    }

    function checkPopout(pos: real): void {
        // pos arrives in root's space; layout is inset by its margin, so
        // convert before testing against layout's children.
        const localPos = pos - (Settings.barHorizontal ? layout.x : layout.y);
        const child = (root.popouts.hasCurrent && withinLockedRegion(localPos)) ? _lockedChild : BarHit.nearestAlong(layout, localPos);
        _lockedChild = child;

        if (child !== tray)
            root.closeTray();

        if (!child) {
            root.popouts.hasCurrent = false;
            return;
        }

        // A sub-target miss (no matching pill/tray index for this exact
        // sample) only closes the popout on fresh arrival at this child --
        // re-evaluating the same already-open child keeps whatever was
        // last showing instead. See the region-hysteresis comment above.
        const reevaluatingSameChild = root.popouts.hasCurrent && child === _lockedChild;

        if (child === statusIcons && Config.bar.popouts.statusIcons) {
            // Same group-aware, tightly-scoped hit-testing as Bar.qml --
            // find which pill localPos actually falls within first, only
            // then search icons inside it.
            const groups = statusIcons.groupContainers;
            let matched = null;
            for (const g of groups) {
                const local = root.alongIn(g.pill, localPos);
                if (local >= 0 && local <= (Settings.barHorizontal ? g.pill.width : g.pill.height)) {
                    matched = g;
                    break;
                }
            }
            // Computed directly from THIS call's own localPos, not read
            // from the pill's separately-maintained hoveredEntry -- see
            // Bar.qml's matching comment for why reading the pill's own
            // state introduced a worse first-entry race than it fixed.
            const icon = matched ? BarHit.nearestAlong(matched.icons, root.alongIn(matched.icons, localPos)) : null;
            if (icon) {
                root.popouts.currentName = icon.name;
                root.popouts.currentCenter = Qt.binding(() => root.centerAlong(icon));
                root.popouts.hasCurrent = true;
            } else if (!reevaluatingSameChild) {
                root.popouts.hasCurrent = false;
            }
        } else if (child === tray && Config.bar.popouts.tray) {
            const hoveringExpandIcon = tray.expandIcon.contains(layout.mapToItem(tray.expandIcon, root.pointAt(localPos)));
            if (!Config.bar.tray.compact || (tray.expanded && !hoveringExpandIcon)) {
                const trayExtent = Settings.barHorizontal ? tray.layout.implicitWidth : tray.layout.implicitHeight;
                const trayStart = Settings.barHorizontal ? tray.x : tray.y;
                const index = Math.floor(((localPos - trayStart - tray.padding * 2 + tray.spacing) / trayExtent) * tray.items.count);
                const trayItem = tray.items.itemAt(index);
                if (trayItem) {
                    root.popouts.currentName = `traymenu${index}`;
                    root.popouts.currentTrayItem = trayItem;
                    root.popouts.currentCenter = Qt.binding(() => root.centerAlong(trayItem));
                    root.popouts.hasCurrent = true;
                } else if (!reevaluatingSameChild) {
                    root.popouts.hasCurrent = false;
                }
            } else {
                root.popouts.hasCurrent = false;
                tray.expanded = true;
            }
        } else {
            root.popouts.hasCurrent = false;
        }
    }

    function handleWheel(pos: real, angleDelta: point): void {
        if (angleDelta.y > 0)
            Audio.incrementVolume();
        else if (angleDelta.y < 0)
            Audio.decrementVolume();
    }

    SignalSurface {
        anchors.fill: parent
        radius: BarLayout.cornerRadius(Settings.barCorners, root.thickness)
        border.width: 0
    }

    // One column when docked to a side, so nothing runs past the strip.
    GridLayout {
        id: layout

        readonly property int crossAlign: Settings.barHorizontal ? Qt.AlignVCenter : Qt.AlignHCenter

        anchors.fill: parent
        anchors.leftMargin: Settings.barHorizontal ? Tokens.padding.medium : 0
        anchors.rightMargin: Settings.barHorizontal ? Tokens.padding.medium : 0
        anchors.topMargin: Settings.barHorizontal ? 0 : Tokens.padding.medium
        anchors.bottomMargin: Settings.barHorizontal ? 0 : Tokens.padding.medium
        flow: Settings.barHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
        rowSpacing: Tokens.spacing.small
        columnSpacing: Tokens.spacing.small

        StyledRect {
            id: startButton

            Layout.alignment: layout.crossAlign

            Layout.preferredWidth: Settings.barInnerWidth
            Layout.preferredHeight: Settings.barInnerWidth
            radius: 0
            color: "transparent"

            AphoticMark {
                anchors.centerIn: parent
                width: parent.width - Tokens.padding.extraSmall * 2
                height: width
            }

            Interact {
                anchors.fill: parent
                radius: parent.radius
                onClicked: root.screenState.launcher = !root.screenState.launcher
            }
        }

        Repeater {
            model: ScriptModel {
                values: Settings.taskbarGrouping ? WindowList.grouped() : WindowList.windows.map(w => ({ appClass: w.appClass, windows: [w] }))
            }

            TaskItem {
                required property var modelData
                group: modelData
                taskbarRoot: root
            }
        }

        Item {
            Layout.fillWidth: Settings.barHorizontal
            Layout.fillHeight: !Settings.barHorizontal
        }

        Tray {
            id: tray

            Layout.alignment: layout.crossAlign
        }

        StatusIcons {
            id: statusIcons

            Layout.alignment: layout.crossAlign
            screenState: root.screenState
        }

        Clock {
            Layout.alignment: layout.crossAlign
            screenState: root.screenState
        }
    }

    // The strip's inner-edge line: the edge away from the screen edge the
    // bar docks to, so the accent reads from the desktop side.
    SignalLine {
        readonly property Item task: root.focusedTaskItem

        horizontal: Settings.barHorizontal
        edge: root.notchEdge
        gapLength: root.screenState.notchSpan
        level: "active"
        activeStart: {
            // Read the task's x/y for the dependency: mapToItem alone
            // would leave this binding stale after the row reflows.
            if (!task)
                return 0;
            const x = task.x, y = task.y;
            const p = task.mapToItem(root, 0, 0);
            return Settings.barHorizontal ? p.x : p.y;
        }
        activeLength: {
            if (!task)
                return 0;
            return Settings.barHorizontal ? task.width : task.height;
        }
    }

    component TaskItem: StyledRect {
        id: item
        property QtObject _sonarTarget: Loader {
            active: Settings.sonarEnabled
            sourceComponent: EchoTarget {
                target: item
                targetId: "core:taskbar/" + item.group.appClass
                label: item.group.appClass
            }
        }

        required property var group
        required property Item taskbarRoot

        readonly property bool isTaskItem: true
        readonly property bool focused: item.group.windows.some(w => w.focused)

        Layout.preferredWidth: Settings.barInnerWidth
        Layout.preferredHeight: Settings.barInnerWidth
        Layout.alignment: Settings.barHorizontal ? Qt.AlignVCenter : Qt.AlignHCenter
        radius: Tokens.rounding.full
        // No fill at all: the strip's Signal line marks the focused task
        // with its accent segment (see the SignalLine below the row).
        color: "transparent"

        AppIcon {
            anchors.centerIn: parent
            appClass: item.group.appClass
            size: parent.width * 0.6
            fontStyle: Tokens.font.icon.large
            colour: Colours.ink
        }

        StyledRect {
            visible: item.group.windows.length > 1
            width: countLabel.implicitWidth + Tokens.padding.extraSmall * 2
            height: countLabel.implicitHeight
            radius: Tokens.rounding.full
            color: Colours.signal
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: -2

            StyledText {
                id: countLabel
                anchors.centerIn: parent
                text: item.group.windows.length
                color: Colours.contrastOn(Colours.signal)
                font: Tokens.font.label.small
            }
        }

        Interact {
            anchors.fill: parent
            radius: parent.radius
            // Interact is a MouseArea and takes LeftButton only by
            // default. Left-click walks the group's windows one at a
            // time; the list of them all moved to right-click, since a
            // popout on every click is in the way of the common case.
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: event => {
                if (event.button === Qt.LeftButton || item.group.windows.length === 1) {
                    WindowList.cycleWindows(item.group.windows);
                    return;
                }
                const popouts = item.taskbarRoot.popouts;
                popouts.currentName = "taskgroup";
                popouts.currentTaskGroup = item.group;
                // Qt.binding(), not a one-shot value -- matches every other
                // popout trigger in this file/Bar.qml. A plain assignment
                // here left currentCenter stale if the taskbar row reflows
                // (a window opens/closes elsewhere) while this popout is
                // still open, since the click already happened and nothing
                // would re-run this expression afterward.
                popouts.currentCenter = Qt.binding(() => item.taskbarRoot.centerAlong(item));
                popouts.hasCurrent = true;
            }
        }
    }
}
