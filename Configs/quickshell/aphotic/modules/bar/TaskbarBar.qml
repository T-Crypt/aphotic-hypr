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

    // Adapted from Bar.qml's own checkPopout -- same tray/statusIcons
    // hit-testing, with the barVertical branching dropped since Taskbar
    // only ever flows its content left-to-right along a single RowLayout.
    function nearestAlongChild(container: Item, pos: real): var {
        if (!container)
            return null;
        let best = null;
        let bestDist = Infinity;
        for (const child of container.children) {
            if (child.width <= 0)
                continue;
            const dist = Math.abs(child.x + child.width / 2 - pos);
            if (dist < bestDist) {
                bestDist = dist;
                best = child;
            }
        }
        return best;
    }

    function centerAlong(item: Item): real {
        return item.mapToItem(root, item.implicitWidth / 2, 0).x;
    }

    function checkPopout(pos: real): void {
        let child = null;
        for (const c of layout.children) {
            if (pos >= c.x && pos <= c.x + c.width) {
                child = c;
                break;
            }
        }

        if (child !== tray)
            root.closeTray();

        if (!child) {
            root.popouts.hasCurrent = false;
            return;
        }

        if (child === statusIcons && Config.bar.popouts.statusIcons) {
            const items = statusIcons.items;
            const localX = layout.mapToItem(items, pos, 0).x;
            const icon = root.nearestAlongChild(items, localX);
            if (icon) {
                root.popouts.currentName = icon.name;
                root.popouts.currentCenter = Qt.binding(() => root.centerAlong(icon));
                root.popouts.hasCurrent = true;
            }
        } else if (child === tray && Config.bar.popouts.tray) {
            const hoveringExpandIcon = tray.expandIcon.contains(layout.mapToItem(tray.expandIcon, pos, 0));
            if (!Config.bar.tray.compact || (tray.expanded && !hoveringExpandIcon)) {
                const trayExtent = tray.layout.implicitWidth;
                const index = Math.floor(((pos - tray.x - tray.padding * 2 + tray.spacing) / trayExtent) * tray.items.count);
                const trayItem = tray.items.itemAt(index);
                if (trayItem) {
                    root.popouts.currentName = `traymenu${index}`;
                    root.popouts.currentTrayItem = trayItem;
                    root.popouts.currentCenter = Qt.binding(() => root.centerAlong(trayItem));
                    root.popouts.hasCurrent = true;
                } else {
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

        IconImage {
            anchors.centerIn: parent
            source: item.group.windows[0]?.icon ?? ""
            implicitSize: parent.width * 0.6
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
                const centerPoint = item.mapToItem(item.taskbarRoot, item.width / 2, 0);
                popouts.currentName = "taskgroup";
                popouts.currentTaskGroup = item.group;
                popouts.currentCenter = centerPoint.x;
                popouts.hasCurrent = true;
            }
        }
    }
}
