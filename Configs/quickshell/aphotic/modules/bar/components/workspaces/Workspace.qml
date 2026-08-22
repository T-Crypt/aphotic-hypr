pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.utils

GridLayout {
    id: root

    required property int index
    required property int activeWsId
    required property var occupied
    required property int groupOffset

    readonly property bool isWorkspace: true // Flag for finding workspace children
    // Unanimated prop for others to use as reference -- the along-axis
    // extent OccupiedBg.qml/ActiveIndicator.qml read via .size
    readonly property int size: (Settings.barVertical ? implicitWidth : implicitHeight) + (hasWindows ? Tokens.padding.extraSmall : 0)

    readonly property int ws: groupOffset + index + 1
    readonly property bool isOccupied: occupied[ws] ?? false
    readonly property bool hasWindows: isOccupied && Config.bar.workspaces.showWindows

    flow: Settings.barVertical ? GridLayout.LeftToRight : GridLayout.TopToBottom
    Layout.alignment: Settings.barVertical ? Qt.AlignVCenter : Qt.AlignHCenter
    Layout.preferredHeight: Settings.barVertical ? -1 : size
    Layout.preferredWidth: Settings.barVertical ? size : -1

    rowSpacing: 0
    columnSpacing: 0

    StyledText {
        id: indicator

        Layout.alignment: Settings.barVertical ? (Qt.AlignVCenter | Qt.AlignLeft) : (Qt.AlignHCenter | Qt.AlignTop)
        Layout.preferredHeight: Settings.barVertical ? -1 : (Settings.barInnerWidth - Tokens.padding.small)
        Layout.preferredWidth: Settings.barVertical ? (Settings.barInnerWidth - Tokens.padding.small) : -1

        animate: true
        text: {
            const ws = Hypr.workspaces.values.find(w => w.id === root.ws);
            const wsName = !ws || ws.name == root.ws ? root.ws : ws.name[0];
            let displayName = wsName.toString();
            if (Config.bar.workspaces.capitalisation.toLowerCase() === "upper") {
                displayName = displayName.toUpperCase();
            } else if (Config.bar.workspaces.capitalisation.toLowerCase() === "lower") {
                displayName = displayName.toLowerCase();
            }
            const label = Config.bar.workspaces.label || displayName;
            const occupiedLabel = Config.bar.workspaces.occupiedLabel || label;
            const activeLabel = Config.bar.workspaces.activeLabel || (root.isOccupied ? occupiedLabel : label);
            return root.activeWsId === root.ws ? activeLabel : root.isOccupied ? occupiedLabel : label;
        }
        color: Config.bar.workspaces.occupiedBg || root.isOccupied || root.activeWsId === root.ws ? Colours.palette.m3onSurface : Colours.layer(Colours.palette.m3outlineVariant, 2)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Qt.AlignVCenter
        font.family: Tokens.font.workspaces
    }

    Loader {
        id: windows

        asynchronous: true

        Layout.alignment: Settings.barVertical ? Qt.AlignVCenter : Qt.AlignHCenter
        Layout.fillHeight: !Settings.barVertical
        Layout.fillWidth: Settings.barVertical
        Layout.topMargin: Settings.barVertical ? 0 : -Settings.barInnerWidth / 10
        Layout.leftMargin: Settings.barVertical ? -Settings.barInnerWidth / 10 : 0

        visible: active
        active: root.hasWindows

        sourceComponent: Grid {
            id: windowIconsGrid

            spacing: 0
            flow: Settings.barVertical ? Grid.LeftToRight : Grid.TopToBottom
            // Grid (unlike GridLayout) has no "no limit" default for the
            // cross axis, so this is pinned to the actual item count
            // instead of a large constant -- large fixed values
            // overflowed rows * columns into a negative capacity.
            columns: Settings.barVertical ? Math.max(1, windowIconsGrid.children.length) : 1
            rows: Settings.barVertical ? 1 : Math.max(1, windowIconsGrid.children.length)

            add: Transition {
                Anim {
                    properties: "scale"
                    from: 0
                    to: 1
                    easing: Tokens.anim.standardDecel
                }
            }

            move: Transition {
                Anim {
                    properties: "scale"
                    to: 1
                    easing: Tokens.anim.standardDecel
                }
                Anim {
                    properties: "x,y"
                }
            }

            Repeater {
                model: ScriptModel {
                    values: {
                        const ws = root.ws;
                        const windows = Hypr.toplevels.values.filter(c => c.workspace?.id === ws);
                        const maxIcons = root.Config.bar.workspaces.maxWindowIcons;
                        return maxIcons > 0 ? windows.slice(0, maxIcons) : windows;
                    }
                }

                MaterialIcon {
                    required property var modelData

                    grade: 0
                    text: Icons.getAppCategoryIcon(modelData.lastIpcObject.class, "terminal")
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }

    Behavior on Layout.preferredHeight {
        Anim {}
    }

    Behavior on Layout.preferredWidth {
        Anim {}
    }
}
