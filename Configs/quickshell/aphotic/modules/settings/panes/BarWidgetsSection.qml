pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// The bar's own widget list, editable in place: Settings.barEntries is the
// same ordered [{ id, enabled }] array Bar.qml renders from, so a toggle or
// a reorder here reaches the bar on the next binding pass with no restart.
ColumnLayout {
    id: root

    required property ScreenState screenState

    // Presentation for each id Bar.qml has a delegate for. `jump` names a
    // Settings category to open, empty where the widget has nowhere of its
    // own to go -- workspaces and statusIcons are configured by sections in
    // this very pane, so sending the reader there would land them back on
    // the page they are already reading.
    //
    // A plugin-contributed widget joins this list in a later pass, from
    // PluginRegistry.surfacesFor("bar") -- the same call Bar.qml's
    // `pluginEntries` already concats onto its own model. Nothing here
    // reads it yet.
    readonly property var catalog: ({
            logo: { icon: "linux", label: qsTr("OS logo"), jump: "" },
            workspaces: { icon: "workspaces", label: qsTr("Workspaces"), jump: "" },
            activeWindow: { icon: "window", label: qsTr("Active window"), jump: "" },
            media: { icon: "music_note", label: qsTr("Media"), jump: "" },
            tray: { icon: "widgets", label: qsTr("System tray"), jump: "" },
            clock: { icon: "schedule", label: qsTr("Clock"), jump: "clock" },
            agent: { icon: "smart_toy", label: qsTr("Agent indicator"), jump: "ai" },
            statusIcons: { icon: "tune", label: qsTr("Status icons"), jump: "" },
            settings: { icon: "settings", label: qsTr("Settings button"), jump: "" },
            power: { icon: "power_settings_new", label: qsTr("Power button"), jump: "power" },
            spacer: { icon: "expand", label: qsTr("Flexible space"), jump: "" },
            gap: { icon: "space_bar", label: qsTr("Fixed gap"), jump: "" }
        })

    // Every operation addresses an entry by array index, never by id:
    // "spacer" legitimately appears more than once, so an id is not a key.
    function describe(id: string): var {
        return root.catalog[id] ?? ({
                icon: "extension",
                label: id,
                jump: ""
            });
    }

    function setEnabled(index: int, value: bool): void {
        const next = Settings.barEntries.map((e, i) => i === index ? ({
                    id: e.id,
                    enabled: value
                }) : e);
        Settings.barEntries = next;
    }

    function move(from: int, to: int): void {
        if (to < 0 || to >= Settings.barEntries.length || from === to)
            return;
        const next = Settings.barEntries.slice();
        const moved = next.splice(from, 1)[0];
        next.splice(to, 0, moved);
        Settings.barEntries = next;
    }

    spacing: Tokens.spacing.small

    StyledText {
        text: qsTr("Widgets")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    StyledText {
        Layout.fillWidth: true
        text: qsTr("Drag the handle to reorder. Disabled widgets leave no gap behind.")
        wrapMode: Text.WordWrap
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
    }

    SettingsGroup {
        Layout.fillWidth: true

        Repeater {
            model: Settings.barEntries

            SettingsRow {
                id: widgetRow

                required property var modelData
                required property int index

                readonly property var info: root.describe(widgetRow.modelData.id)

                icon: widgetRow.info.icon
                label: widgetRow.info.label
                description: widgetRow.modelData.enabled ? "" : qsTr("Hidden")
                opacity: widgetRow.modelData.enabled ? 1 : 0.6

                RowLayout {
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        visible: widgetRow.info.jump.length > 0
                        text: "open_in_new"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            radius: Tokens.rounding.full
                            onClicked: root.screenState.settingsCategory = widgetRow.info.jump
                        }
                    }

                    MaterialIcon {
                        text: widgetRow.modelData.enabled ? "toggle_on" : "toggle_off"
                        fill: 1
                        color: widgetRow.modelData.enabled ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            radius: Tokens.rounding.full
                            onClicked: root.setEnabled(widgetRow.index, !widgetRow.modelData.enabled)
                        }
                    }

                    // Only the handle drags. preventStealing keeps the
                    // settings pane's own Flickable from claiming the
                    // gesture and scrolling the page instead, which it
                    // otherwise does the moment the pointer moves far
                    // enough vertically to count as a flick.
                    MaterialIcon {
                        text: "drag_indicator"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            preventStealing: true
                            cursorShape: Qt.SizeVerCursor

                            property real anchorY: 0

                            onPressed: event => anchorY = mapToItem(null, event.x, event.y).y
                            onPositionChanged: event => {
                                const step = widgetRow.height;
                                if (step <= 0)
                                    return;
                                const y = mapToItem(null, event.x, event.y).y;
                                const delta = y - anchorY;
                                if (Math.abs(delta) < step)
                                    return;
                                const dir = delta > 0 ? 1 : -1;
                                root.move(widgetRow.index, widgetRow.index + dir);
                                anchorY += step * dir;
                            }
                        }
                    }
                }
            }
        }
    }
}
