pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// The command palette's own slot list, editable in place: the notch tile
// renders Settings.paletteEntries directly, so a toggle, a reorder or a
// remap here reaches it on the next binding pass with no restart.
//
// Same ordered [{ id, enabled }] shape the bar's widget list uses, over
// action ids instead of widget ids -- and one thing the bar's list does
// not do, because a bar widget is a fixed set core ships: a slot can be
// pointed at any action in the catalog, core or plugin. That is what
// makes the palette the user's, rather than a fixed list they can only
// hide rows of.
ColumnLayout {
    id: root

    // Which slot the picker is assigning to. -1 with the picker open
    // means it is appending a new one.
    property int pickIndex: -1
    property bool picking: false

    // Actions not already in the list. A palette with the same action
    // twice is legal (nothing breaks) but never what someone meant, so
    // the picker stops offering one already placed.
    readonly property var available: Actions.actions.filter(a => !Settings.paletteEntries.some(e => e.id === a.id))

    function describe(id: string): var {
        return Actions.find(id) ?? ({
                id: id,
                icon: "help",
                label: id,
                plugin: ""
            });
    }

    function setEnabled(index: int, value: bool): void {
        Settings.paletteEntries = Settings.paletteEntries.map((e, i) => i === index ? ({
                    id: e.id,
                    enabled: value
                }) : e);
    }

    function assign(index: int, id: string): void {
        if (index < 0) {
            Settings.paletteEntries = Settings.paletteEntries.concat([
                {
                    id: id,
                    enabled: true
                }
            ]);
            return;
        }
        Settings.paletteEntries = Settings.paletteEntries.map((e, i) => i === index ? ({
                    id: id,
                    enabled: e.enabled
                }) : e);
    }

    function remove(index: int): void {
        Settings.paletteEntries = Settings.paletteEntries.filter((e, i) => i !== index);
    }

    function move(from: int, to: int): void {
        if (to < 0 || to >= Settings.paletteEntries.length || from === to)
            return;
        const next = Settings.paletteEntries.slice();
        const moved = next.splice(from, 1)[0];
        next.splice(to, 0, moved);
        Settings.paletteEntries = next;
    }

    function openPicker(index: int): void {
        root.pickIndex = index;
        root.picking = true;
    }

    spacing: Tokens.spacing.small

    StyledText {
        text: qsTr("Command palette")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    StyledText {
        Layout.fillWidth: true
        text: qsTr("What the notch's Commands tab offers, in this order. Drag the handle to reorder, or swap a slot for any other action. Installing a plugin adds its actions to the list to choose from.")
        wrapMode: Text.WordWrap
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
    }

    SettingsGroup {
        Layout.fillWidth: true
        visible: Settings.paletteEntries.length > 0

        Repeater {
            model: Settings.paletteEntries

            SettingsRow {
                id: slotRow

                required property var modelData
                required property int index

                readonly property var info: root.describe(slotRow.modelData.id)
                // A slot outlives the plugin that supplied its action, on
                // purpose -- see Settings.paletteEntries. It says so here
                // rather than disappearing, which is the only place the
                // user can act on it.
                readonly property bool resolved: Actions.has(slotRow.modelData.id)

                icon: slotRow.info.icon
                label: slotRow.info.label
                description: !slotRow.resolved ? qsTr("Not available right now") : (slotRow.modelData.enabled ? "" : qsTr("Hidden"))
                opacity: slotRow.modelData.enabled && slotRow.resolved ? 1 : 0.6

                RowLayout {
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "swap_horiz"
                        color: root.picking && root.pickIndex === slotRow.index ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            radius: Tokens.rounding.full
                            onClicked: root.openPicker(slotRow.index)
                        }
                    }

                    MaterialIcon {
                        text: "close"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            radius: Tokens.rounding.full
                            onClicked: root.remove(slotRow.index)
                        }
                    }

                    MaterialIcon {
                        text: slotRow.modelData.enabled ? "toggle_on" : "toggle_off"
                        fill: 1
                        color: slotRow.modelData.enabled ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            radius: Tokens.rounding.full
                            onClicked: root.setEnabled(slotRow.index, !slotRow.modelData.enabled)
                        }
                    }

                    // Only the handle drags, and it keeps the pane's own
                    // Flickable from claiming the gesture -- the same
                    // reasoning, and the same shape, as the bar's widget
                    // list.
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
                                const step = slotRow.height;
                                if (step <= 0)
                                    return;
                                const y = mapToItem(null, event.x, event.y).y;
                                const delta = y - anchorY;
                                if (Math.abs(delta) < step)
                                    return;
                                const dir = delta > 0 ? 1 : -1;
                                root.move(slotRow.index, slotRow.index + dir);
                                anchorY += step * dir;
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "add"
            label: qsTr("Add an action")
            description: root.available.length === 0 ? qsTr("Every action is already in the list") : ""
            opacity: root.available.length === 0 ? 0.6 : 1
            activatable: root.available.length > 0
            onActivated: root.openPicker(-1)
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.picking
        text: root.pickIndex < 0 ? qsTr("Pick an action to add") : qsTr("Pick what this slot runs instead")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true
        visible: root.picking

        Repeater {
            // Everything unused, plus whatever the slot being remapped
            // already runs -- that one is filtered out of `available` by
            // its own presence in the list, and leaving it out would make
            // cancelling a remap impossible.
            model: root.picking ? root.available.concat(root.pickIndex >= 0 ? [root.describe(Settings.paletteEntries[root.pickIndex]?.id ?? "")] : []) : []

            SettingsRow {
                id: choiceRow

                required property var modelData

                icon: choiceRow.modelData.icon
                label: choiceRow.modelData.label
                description: choiceRow.modelData.plugin.length > 0 ? qsTr("From a plugin") : ""
                activatable: true

                onActivated: {
                    root.assign(root.pickIndex, choiceRow.modelData.id);
                    root.picking = false;
                    root.pickIndex = -1;
                }
            }
        }
    }
}
