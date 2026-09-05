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

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    required property real thickness

    implicitWidth: thickness
    implicitHeight: layout.implicitHeight + Tokens.padding.small * 2

    function closeTray(): void {
        tray.expanded = false;
    }

    function centerAlong(item: Item): real {
        return item.mapToItem(root, item.implicitWidth / 2, 0).x;
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
        return localPos >= _lockedChild.x - regionHysteresisMargin && localPos <= _lockedChild.x + _lockedChild.width + regionHysteresisMargin;
    }

    function checkPopout(pos: real): void {
        // pos arrives in root's coordinate space (same convention Bar.qml
        // uses), but layout is inset from root by its own leftMargin --
        // unlike Bar.qml's zero-margin Loader, so pos has to be converted
        // into layout-local space before comparing against any of
        // layout's children (including tray/statusIcons's own local
        // geometry) or every hit-test below is off by that margin.
        const localPos = pos - layout.x;
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
            // then search icons inside it. Horizontal-only here (x axis),
            // matching this component's own single RowLayout.
            const groups = statusIcons.groupContainers;
            let matched = null;
            for (const g of groups) {
                const local = layout.mapToItem(g.pill, localPos, 0).x;
                if (local >= 0 && local <= g.pill.width) {
                    matched = g;
                    break;
                }
            }
            // Computed directly from THIS call's own localPos, not read
            // from the pill's separately-maintained hoveredEntry -- see
            // Bar.qml's matching comment for why reading the pill's own
            // state introduced a worse first-entry race than it fixed.
            const icon = matched ? BarHit.nearestAlong(matched.icons, layout.mapToItem(matched.icons, localPos, 0).x) : null;
            if (icon) {
                root.popouts.currentName = icon.name;
                root.popouts.currentCenter = Qt.binding(() => root.centerAlong(icon));
                root.popouts.hasCurrent = true;
            } else if (!reevaluatingSameChild) {
                root.popouts.hasCurrent = false;
            }
        } else if (child === tray && Config.bar.popouts.tray) {
            const hoveringExpandIcon = tray.expandIcon.contains(layout.mapToItem(tray.expandIcon, localPos, 0));
            if (!Config.bar.tray.compact || (tray.expanded && !hoveringExpandIcon)) {
                const trayExtent = tray.layout.implicitWidth;
                const index = Math.floor(((localPos - tray.x - tray.padding * 2 + tray.spacing) / trayExtent) * tray.items.count);
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

    StyledRect {
        anchors.fill: parent
        color: Colours.tPalette.m3surfaceContainer
        radius: 0
    }

    RowLayout {
        id: layout

        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        spacing: Tokens.spacing.small

        StyledRect {
            id: startButton

            Layout.preferredWidth: Settings.barInnerWidth
            Layout.preferredHeight: Settings.barInnerWidth
            radius: Tokens.rounding.full
            color: Colours.palette.m3surfaceContainerHigh

            AphoticMark {
                anchors.centerIn: parent
                width: parent.width - Tokens.padding.extraSmall * 2
                height: width
            }

            StateLayer {
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
            Layout.fillWidth: true
        }

        Tray {
            id: tray
        }

        StatusIcons {
            id: statusIcons
            screenState: root.screenState
        }

        Clock {
            screenState: root.screenState
        }
    }

    component TaskItem: StyledRect {
        id: item

        required property var group
        required property Item taskbarRoot

        readonly property bool focused: item.group.windows.some(w => w.focused)

        Layout.preferredWidth: Settings.barInnerWidth
        Layout.preferredHeight: Settings.barInnerWidth
        radius: Tokens.rounding.full
        color: item.focused ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh

        AppIcon {
            anchors.centerIn: parent
            appClass: item.group.appClass
            size: parent.width * 0.6
            fontStyle: Tokens.font.icon.large
            colour: Colours.palette.m3onSurface
        }

        StyledRect {
            visible: item.group.windows.length > 1
            width: countLabel.implicitWidth + Tokens.padding.extraSmall * 2
            height: countLabel.implicitHeight
            radius: Tokens.rounding.full
            color: Colours.palette.m3primary
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: -2

            StyledText {
                id: countLabel
                anchors.centerIn: parent
                text: item.group.windows.length
                color: Colours.contrastOn(Colours.palette.m3primary)
                font: Tokens.font.label.small
            }
        }

        StateLayer {
            anchors.fill: parent
            radius: parent.radius
            onClicked: {
                if (item.group.windows.length === 1) {
                    WindowList.focus(item.group.windows[0].address);
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
