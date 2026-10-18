pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

// Every workspace as a live map of its windows, laid out to fill the stage.
// Each window is drawn where it actually sits on its monitor, so the tab
// reads like looking down at the desktop rather than a list of icons.
Item {
    id: root

    required property ScreenState screenState

    readonly property var sortedWorkspaces: Hypr.workspaces.values.filter(w => w.id > 0).slice().sort((a, b) => a.id - b.id)
    readonly property int count: Math.max(1, root.sortedWorkspaces.length)

    // The column count whose cells come closest to the monitor's shape.
    readonly property int columns: {
        let best = 1;
        let bestScore = Infinity;
        for (let c = 1; c <= root.count; c++) {
            const rows = Math.ceil(root.count / c);
            const cellAspect = (root.width / c) / Math.max(1, root.height / rows);
            const score = Math.abs(Math.log(cellAspect / 1.7));
            if (score < bestScore) {
                bestScore = score;
                best = c;
            }
        }
        return best;
    }
    readonly property int rows: Math.ceil(root.count / root.columns)

    function monitorOf(ws: var): var {
        const name = ws?.lastIpcObject?.monitor ?? "";
        return (Hypr.monitors?.values ?? []).find(m => m.name === name) ?? null;
    }

    function focusWindow(win: var): void {
        const address = win?.address ?? "";
        if (address)
            WindowList.focus(address.startsWith("0x") ? address : `0x${address}`);
        root.screenState.dashboard = false;
    }

    GridLayout {
        anchors.fill: parent
        columns: root.columns
        columnSpacing: Tokens.spacing.large
        rowSpacing: Tokens.spacing.large

        Repeater {
            model: ScriptModel {
                values: root.sortedWorkspaces
            }

            SignalCard {
                id: wsCard

                required property var modelData
                readonly property bool active: wsCard.modelData.id === Hypr.activeWsId
                readonly property var windows: Hypr.toplevels.values.filter(c => c.workspace?.id === wsCard.modelData.id)
                readonly property var monitor: root.monitorOf(wsCard.modelData)

                title: wsCard.windows.length > 0 ? qsTr("Workspace %1 · %n window(s)", "", wsCard.windows.length).arg(wsCard.modelData.id) : qsTr("Workspace %1").arg(wsCard.modelData.id)
                tintIndex: wsCard.modelData.id
                selected: wsCard.active

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 1

                Interact {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: {
                        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = ${wsCard.modelData.id} })` : `workspace ${wsCard.modelData.id}`);
                        root.screenState.dashboard = false;
                    }
                }

                // The monitor, scaled into the card at its own aspect.
                Item {
                    id: screenArea

                    readonly property real monW: wsCard.monitor?.width ?? 1920
                    readonly property real monH: wsCard.monitor?.height ?? 1080
                    readonly property real monX: wsCard.monitor?.x ?? 0
                    readonly property real monY: wsCard.monitor?.y ?? 0
                    readonly property real availW: parent.width - Tokens.padding.large * 2
                    readonly property real availH: parent.height - wsCard.headerHeight - Tokens.padding.large
                    readonly property real scale: Math.max(0.01, Math.min(screenArea.availW / screenArea.monW, screenArea.availH / screenArea.monH))

                    x: (parent.width - width) / 2
                    y: wsCard.headerHeight + (screenArea.availH - height) / 2
                    width: screenArea.monW * screenArea.scale
                    height: screenArea.monH * screenArea.scale

                    Rectangle {
                        anchors.fill: parent
                        radius: Tokens.rounding.medium
                        color: Qt.alpha(Colours.signalStyle.base, 0.5)
                        border.width: 1
                        border.color: wsCard.active ? Qt.alpha(Colours.signal, 0.5) : Colours.signalStyle.hairline
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: wsCard.windows.length === 0
                        text: qsTr("Empty")
                        color: Colours.inkMuted
                        font: Tokens.font.label.medium
                    }

                    Repeater {
                        model: wsCard.windows

                        Item {
                            id: win

                            required property var modelData
                            readonly property var info: win.modelData.lastIpcObject ?? ({})
                            readonly property bool focused: win.modelData === Hypr.activeToplevel
                            readonly property var at: win.info.at ?? [0, 0]
                            readonly property var size: win.info.size ?? [screenArea.monW, screenArea.monH]

                            x: Math.max(0, (win.at[0] - screenArea.monX) * screenArea.scale)
                            y: Math.max(0, (win.at[1] - screenArea.monY) * screenArea.scale)
                            width: Math.max(18, Math.min(screenArea.width - x, win.size[0] * screenArea.scale))
                            height: Math.max(14, Math.min(screenArea.height - y, win.size[1] * screenArea.scale))

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Math.min(Tokens.rounding.small, height / 3)
                                color: win.focused ? Qt.alpha(Colours.signal, 0.14) : (winArea.containsMouse ? Colours.signalStyle.raisedHi : Colours.signalStyle.raised)
                                border.width: 1
                                border.color: win.focused ? Colours.signal : Colours.signalStyle.hairline

                                Behavior on color {
                                    CAnim {}
                                }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                visible: win.height > 28

                                AppIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    appClass: win.info.class ?? ""
                                    fallbackGlyph: "desktop_windows"
                                    colour: win.focused ? Colours.signal : Colours.inkMuted
                                    size: Math.min(48, Math.max(16, Math.min(win.width, win.height) * 0.32))
                                    fontStyle: Tokens.font.icon.large
                                }

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: win.height > 70 && win.width > 90
                                    width: Math.min(implicitWidth, win.width - 12)
                                    text: win.info.title || win.info.class || ""
                                    elide: Text.ElideRight
                                    color: win.focused ? Colours.ink : Colours.inkMuted
                                    font: Tokens.font.label.small
                                }
                            }

                            MouseArea {
                                id: winArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.focusWindow(win.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
